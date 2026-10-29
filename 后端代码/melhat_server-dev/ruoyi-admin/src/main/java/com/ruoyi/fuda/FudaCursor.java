package com.ruoyi.fuda;
import java.nio.charset.StandardCharsets;
import java.util.*;
public final class FudaCursor {
    private FudaCursor(){}
    public static String encode(FudaAuth.Principal principal,Set<String> keys,long after){
        String payload="2|"+after+"|"+scope(principal,keys);
        String encoded=Base64.getUrlEncoder().withoutPadding().encodeToString(payload.getBytes(StandardCharsets.UTF_8));
        return encoded+"."+FudaAuth.hmac(principal.key,"FUDA-CURSOR\n"+encoded);
    }
    public static long decode(FudaAuth.Principal principal,Set<String> keys,String cursor){
        if(cursor==null)return 0;
        try{
            if(cursor.length()>512)throw new IllegalArgumentException();
            String[] pieces=cursor.split("\\.",-1);if(pieces.length!=2||!pieces[1].matches("[0-9a-f]{64}")||!FudaAuth.equal(pieces[1],FudaAuth.hmac(principal.key,"FUDA-CURSOR\n"+pieces[0])))throw new IllegalArgumentException();
            String[] data=new String(Base64.getUrlDecoder().decode(pieces[0]),StandardCharsets.UTF_8).split("\\|",-1);
            if(data.length!=3||!"2".equals(data[0])||!scope(principal,keys).equals(data[2])||!data[1].matches("0|[1-9][0-9]{0,18}"))throw new IllegalArgumentException();
            long after=Long.parseLong(data[1]);if(after<0)throw new IllegalArgumentException();return after;
        }catch(Exception e){throw new FudaException(400,40002,"Invalid cursor or authorization scope changed");}
    }
    private static String scope(FudaAuth.Principal p,Set<String> keys){List<String> sorted=new ArrayList<>(keys);Collections.sort(sorted);return FudaAuth.sha256((p.appId+"\n"+String.join("\n",sorted)).getBytes(StandardCharsets.UTF_8));}
}
