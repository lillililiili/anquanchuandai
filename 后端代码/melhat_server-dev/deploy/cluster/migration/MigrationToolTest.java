import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Pure data boundary checks; real database round trips are a separate acceptance gate. */
public class MigrationToolTest {
    public static void main(String[] args) throws Exception {
        Path root=Files.createTempDirectory(Path.of(args[0]),"migration-contract-");
        try {
            String first=MigrationTool.canonical(MigrationTool.JSON.readTree("{\"z\":[true,null,1.00],\"a\":{\"水位\":9000000000001,\"照片\":\"帽子🪖\"}}"));
            String second=MigrationTool.canonical(MigrationTool.JSON.readTree("{\"a\":{\"照片\":\"帽子🪖\",\"水位\":9000000000001},\"z\":[true,null,1]}"));
            check(first.equals(second),"semantic JSON preserves Unicode and exact numbers");
            rejected(()->MigrationTool.JSON.readTree("{\"id\":1,\"id\":2}"),"duplicate JSON keys");
            rejected(()->MigrationTool.JSON.readTree("{} {}"),"trailing JSON values");
            for(String path:List.of("../outside","/outside","C:/outside","files/../outside","files\\outside","files//outside"))
                rejected(()->MigrationTool.safe(root,path),"path traversal");
            Path files=root.resolve("files");Files.createDirectory(files);Files.writeString(files.resolve("photo.png"),"original",StandardCharsets.UTF_8);
            var list=MigrationTool.JSON.createArrayNode();var entry=list.addObject();entry.put("path","photo.png");entry.put("bytes",8);entry.put("sha256",MigrationTool.sha(files.resolve("photo.png")));
            MigrationTool.verifyFiles(files,list,true);
            Files.writeString(files.resolve("photo.png"),"modified",StandardCharsets.UTF_8);
            rejected(()->MigrationTool.verifyFiles(files,list,true),"same-size changed file");
            Files.delete(files.resolve("photo.png"));rejected(()->MigrationTool.verifyFiles(files,list,true),"missing photo");
            Path output=root.resolve("sorted.jsonl");
            List<Path> runs=List.of(MigrationTool.writeRun(output,new ArrayList<>(List.of("帽子","2","10"))),MigrationTool.writeRun(output,new ArrayList<>(List.of("1","🪖","a"))));
            MigrationTool.mergeRuns(runs,output);check(Files.readAllLines(output).equals(List.of("1","10","2","a","帽子","🪖")),"deterministic cross-collation sorting");
            Path many=root.resolve("many-runs.jsonl");List<Path> chunks=new ArrayList<>();
            for(int i=70;i>=0;i--)chunks.add(MigrationTool.writeRun(many,new ArrayList<>(List.of(String.format(Locale.ROOT,"%03d",i)))));
            MigrationTool.mergeRuns(chunks,many);check(Files.readAllLines(many).size()==71&&Files.readAllLines(many).get(0).equals("000"),"bounded multi-pass merge");
            rejected(()->MigrationTool.readCharacters(new java.io.Reader(){
                int remaining=MigrationTool.MAX_CELL+1;
                public int read(char[] chars,int start,int length){if(remaining==0)return -1;int n=Math.min(length,remaining);Arrays.fill(chars,start,start+n,'x');remaining-=n;return n;}
                public void close(){}
            }),"oversized text is rejected without truncation");
            var column=new MigrationTool.Column("body","body",java.sql.Types.CLOB,"text",false);
            var table=new MigrationTool.Table("wearable_location","wearable_location",List.of(column),List.of("body"));
            rejected(()->MigrationTool.validateValue(table,column,MigrationTool.JSON.getNodeFactory().textNode("{broken}")),"invalid business JSON");
            System.out.println("PASS: migration serialization, Unicode, traversal, missing/corrupt files, duplicate JSON and deterministic sorting.");
        } finally {try(var walk=Files.walk(root)){for(Path path:walk.sorted(Comparator.reverseOrder()).toList())Files.deleteIfExists(path);}}
    }
    interface Work {void run()throws Exception;}
    static void rejected(Work work,String message)throws Exception{boolean refused=false;try{work.run();}catch(Exception expected){refused=true;}check(refused,message);}
    static void check(boolean condition,String message){if(!condition)throw new AssertionError(message);}
}
