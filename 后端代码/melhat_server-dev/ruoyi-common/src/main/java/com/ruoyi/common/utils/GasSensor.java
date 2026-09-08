package com.ruoyi.common.utils;
/*
四合一气体传感器
参数：默认地址01   波特率 9600
TX:01 03 00 20 00 08 45 C6
RX:01 03 10 00 00 00 01 00 00 00 D2 00 00 00 00 00 00 00 00 62 7D
解析：
01 03 10

00 00 :
00 01 :
00 00 :
00 D2 :
00 00 :
00 00 :
00 00 :
00 00 :
62 7D
 */
public class GasSensor {
    //======================设备命令区==============================//

    //======================变量定义===============================//
    public byte[] SendBytes = new byte[20];//发送数据缓冲区
    public int SendBytesLen;//发送数据缓冲区长度
    public byte[] RecvBytes = new byte[100];//接收数据缓冲区
    public int RecvBytesLen;//接收数据缓冲区长度
    //=====================气体含量区==================================//
    //甲烷、氧气、一氧化碳、硫化氢
    public float CH4Content = 0;
    public String CH4ContentString;
    public float O2Content = 0;
    public String O2ContentString;
    public float COContent = 0;
    public String COContentString;
    public float H2SContent = 0;
    public String H2SContentString;
    //=====================功能函数=================================//
    /*
    函数功能：查询4合一气体传感器的指令
     */
    public int CXGasSensorCmd(){
        //01 03 00 20 00 08
        SendBytesLen = 8;
        SendBytes[0] = 0x01;
        SendBytes[1] = 0x03;
        SendBytes[2] = 0x00;
        SendBytes[3] = 0x20;
        SendBytes[4] = 0x00;
        SendBytes[5] = 0x08;
        SendBytes[6] = 0x45;
        SendBytes[7] = (byte)0x0C6;
        return SendBytesLen;
    }
    /*
    函数：JXGasSensorData 解析接收数据包
    输入：in_buf 接收的BTYE型缓冲区首地址
            in_buflen 接收的数据长度
    输出：CH4Content       甲烷气体含量float型
            CH4ContentString    甲烷气体含量string型
            O2Content       氧气气体含量float型
            O2ContentString    氧气气体含量string型
            COContent       一氧化碳气体含量float型
            COContentString    一氧化碳气体含量string型
            H2SContent       硫化氢气体含量float型
            H2SContentString    硫化氢气体含量string型
    返回值：0  接收的数据效验出错    1  接收数据正常
     */
    public int JXGasSensorData(byte[] in_buf,int in_buflen) {
        int wh_m_datapos = 3;
        //int wh_CRCJSreslut = CRC_modbus16(in_buf,in_buflen-2);//getCRC
        int wh_CRCJSreslut = CRC_modbus16(in_buf,in_buflen-2);//getCRC
        System.out.println("JXGasSensorData-wh_CRCJSreslut:" + String.valueOf(wh_CRCJSreslut));
        int wh_CRCDatareslut = toIntLHByIndex(in_buf,in_buflen-2,2);
        System.out.println("JXGasSensorData-wh_CRCDatareslut:" + String.valueOf(wh_CRCDatareslut));
        if(wh_CRCJSreslut == wh_CRCDatareslut)
        {
            //甲烷、氧气、一氧化碳、硫化氢
            //======================甲烷(原数据)==========================//
            //状态
            wh_m_datapos += 2;
            //数据
            CH4Content = (float)toIntHHTwoBytesByIndex(in_buf,wh_m_datapos);
            CH4ContentString = String.valueOf(CH4Content);
            wh_m_datapos += 2;
            //======================氧气（扩大10倍）==========================//
            //状态
            wh_m_datapos += 2;
            //数据
            O2Content = (float)toIntHHTwoBytesByIndex(in_buf,wh_m_datapos);
            O2Content = O2Content / 10;
            O2ContentString = String.valueOf(O2Content);
            wh_m_datapos += 2;
            //======================一氧化碳(原数据)==========================//
            //状态
            wh_m_datapos += 2;
            //数据
            COContent = (float)toIntHHTwoBytesByIndex(in_buf,wh_m_datapos);
            COContentString = String.valueOf(COContent);
            wh_m_datapos += 2;
            //=======================硫化氢(原数据)=========================//
            //状态
            wh_m_datapos += 2;
            //数据
            H2SContent = (float)toIntHHTwoBytesByIndex(in_buf,wh_m_datapos);
            H2SContentString = String.valueOf(H2SContent);
            wh_m_datapos += 2;
            return 1;
        }
        return 0;
    }
    public int CRC_modbus16(byte[] bytes,int bytelen) {
        int CRC = 0x0000ffff;
        int POLYNOMIAL = 0x0000a001;
        int i, j;
        for (i = 0; i < bytelen; i++) {
            CRC ^= ((int) bytes[i] & 0x000000ff);
            for (j = 0; j < 8; j++) {
                if ((CRC & 0x00000001) != 0) {
                    CRC >>= 1;
                    CRC ^= POLYNOMIAL;
                } else {
                    CRC >>= 1;
                }
            }
        }
        return CRC;
    }
    /*
    byte[] 转 int 低字节在前
     */
    public int toIntLH(byte[] b){
        int res = 0;
        for(int i=0;i<b.length;i++){
            res += (b[i] & 0x0ff) << (i*8);
        }
        return res;
    }
    public int toIntLHByIndex(byte[] b,int in_index,int in_len){
        int res = 0;
        byte[] bytes = new byte[4];
        java.util.Arrays.fill(bytes, (byte) 0);
        System.arraycopy(b,in_index,
                bytes,0,in_len);
        res = toIntLH(bytes);
        return res;
    }
    //高在前
    public int toIntHHTwoBytesByIndex(byte[] b,int in_index){
        int res = 0;
        byte[] bytes = new byte[4];
        java.util.Arrays.fill(bytes, (byte) 0);
        bytes[0] = b[in_index+1];
        bytes[1] = b[in_index];
        res = toIntLH(bytes);
        return res;
    }
    //===================================类型转换==================================================//
    /**
     * Byte字节转Hex
     * @param
     * @return Hex
     */
    public static String byteToHex(byte b)
    {
        String hexString = Integer.toHexString(b & 0xFF);
        //由于十六进制是由0~9、A~F来表示1~16，所以如果Byte转换成Hex后如果是<16,就会是一个字符（比如A=10），通常是使用两个字符来表示16进制位的,
        //假如一个字符的话，遇到字符串11，这到底是1个字节，还是1和1两个字节，容易混淆，如果是补0，那么1和1补充后就是0101，11就表示纯粹的11
        if (hexString.length() < 2)
        {
            hexString = new StringBuilder(String.valueOf(0)).append(hexString).toString();
        }
        return hexString.toUpperCase();
    }
    /**
     * 字节数组转Hex
     * @param bytes 字节数组
     * @return Hex
     */
    public static String bytesToHex(byte[] bytes) {
        StringBuffer sb = new StringBuffer();
        if (bytes != null && bytes.length > 0) {
            for (int i = 0; i < bytes.length; i++) {
                String hex = byteToHex(bytes[i]);
                sb.append(hex);
            }
        }
        return sb.toString();
    }
    /**
     * Hex转Byte字节
     * @param hex 十六进制字符串
     * @return 字节
     */
    public static byte hexToByte(String hex)
    {
        return (byte) Integer.parseInt(hex,16);
    }
    /**
     * Hex转Byte字节数组
     * @param hex 十六进制字符串
     * @return 字节数组
     */
    public static byte[] hexToBytes(String hex)
    {
        int hexLength = hex.length();
        byte[] result;
        //判断Hex字符串长度，如果为奇数个需要在前边补0以保证长度为偶数
        //因为Hex字符串一般为两个字符，所以我们在截取时也是截取两个为一组来转换为Byte。
        if (hexLength % 2 ==1)
        {
            //奇数
            hexLength++;
            hex = "0"+hex;
        }
        result = new byte[(hexLength/2)];
        int j = 0;
        for (int i = 0; i < hexLength; i+=2) {
            result[j] = hexToByte(hex.substring(i,i+2));
            j++;
        }
        return result;
    }
}
