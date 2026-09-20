package com.ruoyi.portal.demo;

import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.*;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import com.fasterxml.jackson.databind.ObjectMapper;

@Component @Profile("portal-demo")
public class DemoBootstrap implements ApplicationRunner {
    private final JdbcTemplate db; private final TransactionTemplate tx;
    public DemoBootstrap(JdbcTemplate db,PlatformTransactionManager tm){this.db=db;this.tx=new TransactionTemplate(tm);}
    @Override public void run(ApplicationArguments args)throws Exception {
        if(!"wearable_portal_demo".equals(db.queryForObject("SELECT DATABASE()",String.class))||!"wearable-portal-demo".equals(db.queryForObject("SELECT environment FROM portal_demo_schema WHERE version=1",String.class)))throw new IllegalStateException("Refusing non-demo database");
        if(db.queryForObject("SELECT COUNT(*) FROM sys_user",Integer.class)>0){repairInitialPasswords();return;}
        Map<String,String> passwords=new LinkedHashMap<>();
        for(String name:Arrays.asList("demo_owner","demo_verifier","demo_reader")){byte[] b=new byte[15];new SecureRandom().nextBytes(b);passwords.put(name,Base64.getUrlEncoder().withoutPadding().encodeToString(b));}
        Path file=Paths.get("/demo-runtime/accounts.local.json");Files.createDirectories(file.getParent());
        if(Files.exists(file))passwords=new ObjectMapper().readValue(Files.readAllBytes(file),LinkedHashMap.class);
        else Files.write(file,new ObjectMapper().writerWithDefaultPrettyPrinter().writeValueAsBytes(passwords),StandardOpenOption.CREATE_NEW);
        final Map<String,String> credentials=passwords;
        tx.execute(status->{
            db.update("INSERT INTO sys_dept(dept_id,dept_name,ancestors) VALUES(900,'模拟演示组织','0')");
            List<String> perms=Arrays.asList("portal:person:read","portal:person:history","portal:location:read","portal:track:read","portal:fence:read","portal:material:read","portal:video:read","portal:event:read","portal:event:verification:read","portal:equipment:assign","portal:fence:write","portal:material:write","portal:event:claim","portal:event:transfer","portal:event:verification:write","portal:event:complete","portal:demo:control");
            for(int i=0;i<perms.size();i++)db.update("INSERT INTO sys_menu(menu_id,menu_name,menu_type,perms,status) VALUES(?,?,'F',?,'0')",9000+i,perms.get(i),perms.get(i));
            String[] names={"demo_owner","demo_verifier","demo_reader"},labels={"演示负责人","演示核验员","只读查看员"};
            for(int i=0;i<3;i++){
                int id=9001+i;db.update("INSERT INTO sys_role(role_id,role_name,role_key,role_sort,status) VALUES(?,?,?,?, '0')",id,labels[i],names[i],i);
                db.update("INSERT INTO sys_user(user_id,dept_id,user_name,nick_name,password,status,del_flag) VALUES(?,900,?,?,?,'0','0')",id,names[i],labels[i],new BCryptPasswordEncoder().encode(credentials.get(names[i])));
                db.update("INSERT INTO sys_user_role(user_id,role_id) VALUES(?,?)",id,id);
                for(int j=0;j<perms.size();j++)if(i==0||j<9||i==1&&Arrays.asList("portal:event:claim","portal:event:verification:write","portal:material:write").contains(perms.get(j)))db.update("INSERT INTO sys_role_menu(role_id,menu_id) VALUES(?,?)",id,9000+j);
            }
            for(int s=1;s<=3;s++){
                String site="demo-site-"+s;db.update("INSERT INTO portal_site VALUES(?,?,?)",site,s==3?"模拟空厂站":"模拟厂站"+s,"Asia/Shanghai");
                for(int a=9001;a<=9003;a++)if(a==9001||s!=2)db.update("INSERT INTO portal_site_grant VALUES(?,?)",a,site);
                db.update("INSERT INTO portal_area VALUES(?,?,?)","area-"+s,site,"模拟作业区");
                db.update("INSERT INTO portal_team VALUES(?,?,?)","team-"+s,site,"模拟检修班组");
                db.update("INSERT INTO portal_shift(id,site_id,name) VALUES(?,?,?)","shift-"+s,site,"模拟当班名册");
                if(s==3)continue;
                for(int p=1;p<=25;p++){
                    String person="person-"+s+"-"+p;db.update("INSERT INTO portal_person(id,site_id,code,name,team_id,area_id,shift_id) VALUES(?,?,?,?,?,?,?)",person,site,String.format("DEMO-P-%d-%03d",s,p),"模拟人员"+s+"-"+p,"team-"+s,"area-"+s,"shift-"+s);
                    db.update("INSERT INTO portal_roster VALUES(?,?,?)",person,site,"shift-"+s);
                    for(String type:Arrays.asList("HELMET","BELT","WATCH"))db.update("INSERT INTO portal_device(id,site_id,code,type,communication,source_time) VALUES(?,?,?,?,?,UTC_TIMESTAMP(3))","device-"+s+"-"+p+"-"+type,site,"DEMO-"+s+"-"+p+"-"+type,type,p%3==0?"OFFLINE":p%3==1?"ONLINE":"UNKNOWN");
                }
            }
            return null;
        });
    }
    /** One-time repair of the initial 24-character fixture, never reset user-changed passwords. */
    private void repairInitialPasswords() throws Exception {
        Path file=Paths.get("/demo-runtime/accounts.local.json");if(!Files.exists(file))return;
        Map<String,String> credentials=new ObjectMapper().readValue(Files.readAllBytes(file),LinkedHashMap.class);
        boolean needsRepair=credentials.values().stream().anyMatch(p->p.length()>20);if(!needsRepair)return;
        BCryptPasswordEncoder encoder=new BCryptPasswordEncoder();
        tx.execute(status->{for(String name:Arrays.asList("demo_owner","demo_verifier","demo_reader")){
            String old=credentials.get(name);if(old==null||old.length()<=20)continue;
            String next=old.substring(0,20),current=db.queryForObject("SELECT password FROM sys_user WHERE user_name=? AND user_id IN (9001,9002,9003)",String.class,name);
            if(!encoder.matches(old,current)&&!encoder.matches(next,current))throw new IllegalStateException("Demo password changed; automatic repair refused");
            db.update("UPDATE sys_user SET password=? WHERE user_name=? AND user_id IN (9001,9002,9003)",encoder.encode(next),name);credentials.put(name,next);
        }return null;});
        Path temporary=file.resolveSibling("accounts.local.json.pending");
        Files.write(temporary,new ObjectMapper().writerWithDefaultPrettyPrinter().writeValueAsBytes(credentials));
        Files.move(temporary,file,StandardCopyOption.REPLACE_EXISTING);
    }
}
