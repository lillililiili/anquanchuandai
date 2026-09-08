//package com.ruoyi.common.utils;
//
//import com.ruoyi.common.utils.spring.SpringUtils;
//import gnu.io.*;
//import lombok.extern.slf4j.Slf4j;
//import org.springframework.beans.factory.annotation.Value;
//import org.springframework.stereotype.Component;
//
//import javax.annotation.PostConstruct;
//import java.io.IOException;
//import java.io.InputStream;
//import java.io.OutputStream;
//import java.util.*;
//import java.util.concurrent.ExecutorService;
//import java.util.concurrent.Executors;
//
///**
// * TODO
// *
// * @author linfeng
// * @date 2022/4/24 14:57
// */
//@Component
//@Slf4j
//public class SerialPortUtil {
//
//    @Value("${ruoyi.serialPort}")
//    private String portName; //本地COM口
//    private static CommPortIdentifier commPortIdentifier;
//    private static SerialPort serialPort;
//    private static OutputStream out;
//    private static InputStream in;
//    private static int baud = 9600;
//
//
////    @PostConstruct
//    public void init() {
//        //打开串口
//        try {
//            commPortIdentifier = CommPortIdentifier.getPortIdentifier(portName);
//            serialPort = (SerialPort) commPortIdentifier.open(portName,2000);
//            // 注册一个SerialPortEventListener事件来监听串口事件
//            serialPort.addEventListener(new SerialPortListener());
//            // 数据可用则触发事件
//            serialPort.notifyOnDataAvailable(true);
//            // 打开输入输出流
//            in = serialPort.getInputStream();
//            // 设置串口参数，波特率9600，8位数据位，1位停止位，无奇偶校验
//            serialPort.setSerialPortParams(baud, SerialPort.DATABITS_8, SerialPort.STOPBITS_1, SerialPort.PARITY_NONE);
//        } catch (Exception e) {
//            log.error("串口-{}连接失败...",portName,e);
//        }
//        log.info("已连接串口-{}",portName);
//
//        GasSensor gasSensor = new GasSensor();
//
//        new Thread(new Runnable() {
//            public void run() {
//                    new Timer().schedule(new TimerTask() {
//                        @Override
//                        public void run() {
//                            log.info(new Date(scheduledExecutionTime())+"========解析一串接收数据===========");
//                                jx(gasSensor);//解析数据
//
//                        }
//                    },100,5000);
//            }
//        }).start();
//    }
//
//    private void jx(GasSensor gasSensor){
//        byte[] wh_g_recvbuf = new byte[30];//发送数据缓冲区
////                            int sensor = gasSensor.CXGasSensorCmd();
////                            log.info("发送数据缓冲区===>>"+gasSensor.bytesToHex(gasSensor.SendBytes));
//        wh_g_recvbuf[0] = 0x01;
//        wh_g_recvbuf[1] = 0x03;
//        wh_g_recvbuf[2] = 0x10;
//        wh_g_recvbuf[3] = 0x00;
//        wh_g_recvbuf[4] = 0x00;
//        wh_g_recvbuf[5] = 0x00;
//        wh_g_recvbuf[6] = 0x01;
//        wh_g_recvbuf[7] = 0x00;
//        wh_g_recvbuf[8] = 0x00;
//        wh_g_recvbuf[9] = 0x00;
//        wh_g_recvbuf[10] = (byte)0x0D2;
//        wh_g_recvbuf[11] = 0x00;
//        wh_g_recvbuf[12] = 0x00;
//        wh_g_recvbuf[13] = 0x00;
//        wh_g_recvbuf[14] = 0x00;
//        wh_g_recvbuf[15] = 0x00;
//        wh_g_recvbuf[16] = 0x00;
//        wh_g_recvbuf[17] = 0x00;
//        wh_g_recvbuf[18] = 0x00;
//        wh_g_recvbuf[19] = 0x62;
//        wh_g_recvbuf[20] = (byte)0x7D;
//        if(gasSensor.JXGasSensorData(wh_g_recvbuf,21) == 1) {
//            log.info("甲烷：" + gasSensor.CH4ContentString + "%");
//            log.info("氧气：" + gasSensor.O2ContentString + "%");
//            log.info("一氧化碳：" + gasSensor.COContentString + " 10^-6");
//            log.info("硫化氢：" + gasSensor.H2SContentString + " 10^-6");
//        } else {
//            log.error("气体数据解析错误");
//        }
//
//        if(true){//超标后告警
//            //TODO 挪到system模块 调用service
//            /*一氧化碳超标报警	31
//            甲烷超标报警	32
//            硫化氢超标报警	33
//            氧气超标报警	34*/
////            TabSos record = new TabSos("气体检测设备", 31, null,null, "1");
////            //记录保存
////            ITabSosService tabSosService = SpringUtils.getBean(ITabSosService.class);
////            tabSosService.insertTabSos(record);
//
//        }
//    }
//
//
//
//    public class SerialPortListener implements SerialPortEventListener{
//        @Override
//        public void serialEvent(SerialPortEvent serialPortEvent){
//            switch (serialPortEvent.getEventType()) {
//                case SerialPortEvent.DATA_AVAILABLE:
//                    //Data available at the serial port，端口有可用数据。读到缓冲数组，输出到终端
//                    System.out.println("端口有可用数据");
//                    try {
//                        if (in != null) {
//                            //缓冲区可自己修改
//                            byte[] cache = new byte[12];
//                            int availableBytes = 0;
//                            availableBytes = in.available();
//                            while (availableBytes > 0) {
//                                in.read(cache);
//                                String[] data = bytes2HexString(cache).split(" ");
//                                System.out.println(bytes2HexString(cache));
//                            }
//                        }
//                    }catch (Exception e) {
//                        log.error("气体检测异常",e);
//                    }
//                    break;
//                case SerialPortEvent.BI:
//                    //Break interrupt,通讯中断
//                    log.error("通讯中断");
//                    break;
//                case SerialPortEvent.OE:
//                    //Overrun error，溢位错误
//                    log.error("溢位错误");
//                    break;
//                case SerialPortEvent.FE:
//                    //Framing error，传帧错误
//                    log.error("传帧错误");
//                    break;
//                case SerialPortEvent.PE:
//                    //Parity error，校验错误
//                    log.error("校验错误");
//                    break;
//                case SerialPortEvent.CD:
//                    //Carrier detect，载波检测
//                    log.error("载波检测");
//                    break;
//                case SerialPortEvent.CTS:
//                    //Clear to send，清除发送
//                    log.error("清除发送");
//                    break;
//                case SerialPortEvent.DSR:
//                    // Data set ready，数据设备就绪
//                    log.error("数据设备就绪");
//                    break;
//                case SerialPortEvent.RI:
//                    //Ring indicator，响铃指示
//                    log.error("响铃指示");
//                    break;
//                case SerialPortEvent.OUTPUT_BUFFER_EMPTY:
//                    // Output buffer is empty，输出缓冲区清空
//                    log.error("监听端口出现了异常");
//                    break;
//            }
//        }
//    }
//    /*
//     * 字节数组转16进制字符串
//     */
//    public String bytes2HexString(byte[] b){
//        String r = "";
//        for (int i = 0; i < b.length; i++) {
//            String hex = Integer.toHexString(b[i] & 0xFF);
//            if (hex.length() == 1) {
//                hex = '0' + hex;
//            }
//            r += hex.toUpperCase()+" ";
//        }
//        return r;
//    }
//
//    /**
//     * 获取系统com端口
//     * @return
//     */
//    public String getSystemSerialPort(){
//        Enumeration<CommPortIdentifier> portList = CommPortIdentifier.getPortIdentifiers();
//        String portName ="";
//        while (portList.hasMoreElements()) {
//            portName = portList.nextElement().getName();
//            System.out.println(portName);
//        }
//        return portName;
//    }
//
//}