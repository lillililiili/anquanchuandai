package com.ruoyi.guardian;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.UUID;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

class GuardianSharedFilesTest {
    @TempDir Path root;
    private static final String ID = "upload-12345678-1234-1234-1234-123456789abc";
    private static final byte[] PNG = {(byte)137,80,78,71,13,10,26,10,1};
    private static final byte[] JPG = {(byte)255,(byte)216,(byte)255,2};
    private static final String STORE_ID = "31714061-4966-4eef-b3f1-febcb385b858";
    private JdbcTemplate database() {
        return new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:files"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE", "sa", ""));
    }
    @Test void publishedOnOneNodeReadAndOverwrittenOnAnother() {
        JdbcTemplate db=database();
        GuardianFiles a=new GuardianFiles(root,new GuardianFileCatalog(db));
        GuardianFiles b=new GuardianFiles(root,new GuardianFileCatalog(db));
        a.save(ID,"image/png",new ByteArrayInputStream(PNG));
        assertArrayEquals(PNG,b.read(ID).bytes);
        b.save(ID,"image/jpeg",new ByteArrayInputStream(JPG));
        assertEquals("image/jpeg",a.read(ID).type);
        assertArrayEquals(JPG,a.read(ID).bytes);
    }
    @Test void concurrentWritersPublishOnlyCompleteMatchingContent() throws Exception {
        JdbcTemplate db=database();
        GuardianFiles a=new GuardianFiles(root,new GuardianFileCatalog(db));
        GuardianFiles b=new GuardianFiles(root,new GuardianFileCatalog(db));
        ExecutorService pool=Executors.newFixedThreadPool(2);
        CountDownLatch start=new CountDownLatch(1);
        try {
            Future<?> one=pool.submit(()->{await(start);a.save(ID,"image/png",new ByteArrayInputStream(PNG));});
            Future<?> two=pool.submit(()->{await(start);b.save(ID,"image/jpeg",new ByteArrayInputStream(JPG));});
            start.countDown();one.get(10,TimeUnit.SECONDS);two.get(10,TimeUnit.SECONDS);
            GuardianFiles.Stored stored=a.read(ID);
            assertArrayEquals("image/png".equals(stored.type)?PNG:JPG,stored.bytes);
            assertEquals(1,db.queryForObject("select count(*) from guardian_file_publication",Integer.class));
        } finally {pool.shutdownNow();}
    }
    @Test void databaseFailureCannotFallBackToOldPhotoOrReturnSuccess() throws Exception {
        JdbcTemplate db=database();GuardianFiles files=new GuardianFiles(root,new GuardianFileCatalog(db));
        Files.write(root.resolve(ID+".png"),PNG);
        db.execute("drop table guardian_file_publication");
        assertThrows(GuardianRejected.class,()->files.read(ID));
        assertThrows(GuardianRejected.class,()->files.save(ID,"image/jpeg",new ByteArrayInputStream(JPG)));
    }
    @Test void corruptedOrMissingPublishedFileFailsExplicitly() throws Exception {
        JdbcTemplate db=database();GuardianFiles files=new GuardianFiles(root,new GuardianFileCatalog(db));
        files.save(ID,"image/png",new ByteArrayInputStream(PNG));
        String name=db.queryForObject("select file_name from guardian_file_publication where file_id=?",String.class,ID);
        Files.write(root.resolve(name),JPG);
        assertThrows(GuardianRejected.class,()->files.read(ID));
        Files.delete(root.resolve(name));
        assertThrows(GuardianRejected.class,()->files.read(ID));
    }
    @Test void existingLegacyPhotosRemainReadableAndInvalidContentDoesNotReplaceThem() throws Exception {
        GuardianFiles files=new GuardianFiles(root,new GuardianFileCatalog(database()));
        Files.write(root.resolve(ID+".png"),PNG);
        assertArrayEquals(PNG,files.read(ID).bytes);
        assertThrows(GuardianRejected.class,()->files.save(ID,"image/png",new ByteArrayInputStream(JPG)));
        assertArrayEquals(PNG,files.read(ID).bytes);
    }
    @Test void storageProbeDetectsInvalidMountWithoutPublishingPhoto() throws Exception {
        GuardianFiles good=new GuardianFiles(root,null);
        assertTrue(good.storageReady());
        Path file=Files.write(root.resolve("file-not-directory"),new byte[]{1});
        assertFalse(new GuardianFiles(file,null).storageReady());
        try(java.util.stream.Stream<Path> entries=Files.list(root)) {assertEquals(1,entries.count());}
    }
    @Test void clusterRequiresConfiguredStoreId() {
        assertThrows(IllegalStateException.class,()->new GuardianFiles(root.toString(),null,true,""));
    }
    @Test void clusterFailsClosedForAbsentRootAndMissingOrWrongMarker() throws IOException {
        JdbcTemplate db=database();
        Path mount=root.resolve("mounted");
        GuardianFiles files=new GuardianFiles(mount,new GuardianFileCatalog(db),STORE_ID);
        assertUnavailable(files);
        assertFalse(Files.exists(mount));

        Files.createDirectory(mount);
        assertUnavailable(files);
        Path marker=mount.resolve(".wearable-store-id");
        assertFalse(Files.exists(marker));

        Files.write(marker,("different-store\n").getBytes(StandardCharsets.UTF_8));
        Files.write(mount.resolve(ID+".png"),PNG);
        assertUnavailable(files);
        assertEquals(0,db.queryForObject("select count(*) from guardian_file_publication",Integer.class));
        try(java.util.stream.Stream<Path> entries=Files.list(mount)) {assertEquals(2,entries.count());}

        Files.write(marker,(STORE_ID+"\n").getBytes(StandardCharsets.UTF_8));
        assertTrue(files.storageReady());
        files.save(ID,"image/jpeg",new ByteArrayInputStream(JPG));
        assertArrayEquals(JPG,files.read(ID).bytes);

        Files.delete(marker);
        assertUnavailable(files);
        assertFalse(Files.exists(marker));
    }
    @Test void symlinkedMarkerCannotAuthorizeTheRoot() throws IOException {
        Path target=Files.write(root.resolve("elsewhere"),(STORE_ID+"\n").getBytes(StandardCharsets.UTF_8));
        try {
            Files.createSymbolicLink(root.resolve(".wearable-store-id"),target);
        } catch(FileSystemException | UnsupportedOperationException error) {
            org.junit.jupiter.api.Assumptions.assumeTrue(false,"Host cannot create symbolic links: "+error.getMessage());
        }
        assertUnavailable(new GuardianFiles(root,new GuardianFileCatalog(database()),STORE_ID));
    }
    @Test void createOnlyCannotReplacePublishedOrLegacyContent() throws IOException {
        JdbcTemplate db=database();
        GuardianFiles one=new GuardianFiles(root,new GuardianFileCatalog(db));
        GuardianFiles two=new GuardianFiles(root,new GuardianFileCatalog(db));
        String legacy="upload-a2345678-1234-1234-1234-123456789abc";
        Files.write(root.resolve(legacy+".png"),PNG);
        one.prepareCreate(ID,"image/png",new ByteArrayInputStream(PNG)).run();
        for(String used:new String[]{ID,legacy}) {
            AdminQueryService.QueryFailed rejected=assertThrows(AdminQueryService.QueryFailed.class,
                    ()->two.prepareCreate(used,"image/jpeg",new ByteArrayInputStream(JPG)).run());
            assertEquals("FILE_EXISTS",rejected.errorCode);
            assertArrayEquals(PNG,two.read(used).bytes);
        }
    }
    @Test void atomicRenameFailureCannotPublishPointer() throws IOException {
        JdbcTemplate db=database();
        Files.write(root.resolve(".wearable-store-id"),(STORE_ID+"\n").getBytes(StandardCharsets.UTF_8));
        GuardianFiles files=new GuardianFiles(root,new GuardianFileCatalog(db),STORE_ID) {
            @Override void move(Path source,Path target) throws IOException {
                throw new AtomicMoveNotSupportedException(source.toString(),target.toString(),"test filesystem");
            }
        };
        assertFalse(files.storageReady());
        assertThrows(GuardianRejected.class,()->files.save(ID,"image/png",new ByteArrayInputStream(PNG)));
        assertNull(files.read(ID));
        assertEquals(0,db.queryForObject("select count(*) from guardian_file_publication where file_name is not null",Integer.class));
        try(java.util.stream.Stream<Path> entries=Files.list(root)) {assertEquals(1,entries.count());}
    }
    private static void assertUnavailable(GuardianFiles files) {
        assertFalse(files.storageReady());
        assertThrows(GuardianRejected.class,()->files.read(ID));
        assertThrows(GuardianRejected.class,()->files.save(ID,"image/png",new ByteArrayInputStream(PNG)));
    }
    private static void await(CountDownLatch latch) {try {latch.await();}catch(InterruptedException e){Thread.currentThread().interrupt();throw new RuntimeException(e);}}
}
