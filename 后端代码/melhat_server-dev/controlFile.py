import redis #缓存
import os #文件
import threading #线程
import time #时间
import re #正则
import shutil #文件工具
import schedule #定时器
import sys

# todo 最好改成有默认值还能通过脚本传参的方式,方便后续启动优化,不过py脚本可以直接修改,也不用这么麻烦
args = sys.argv


red = redis.Redis(host="192.168.1.109", port=6377, db=0, password="123456")
# videoFrom = "/usr/local/nginx/video"
videoFrom = "E:\\from" #trmp推流视频目录
videoTo = "E:\\to" #风电上传文件目录
videoDead = "E:\\dead" #临时存放目录

rs_reg_key = "VIDEO_FILE_LIST"
rs_video_num = "VIDEO_TRMP_NUM"
re_video_move_num = "VIDEO_TRMP_MOVE_NUM"

t = os.walk(videoFrom)

if red == None:
    raise Exception('reids连接失败,请检查配置信息')
if not os.path.exists(videoFrom):
    os.makedirs(videoFrom)  # 如果没有指定的上传目录,则递归创建
if not os.path.exists(videoTo):
    os.makedirs(videoTo)  # 如果没有指定的上传目录,则递归创建

"""
定时器删除文件开始-------------------
这块还有问题,定时器并没有循环执行??
"""

def job():
    """
    线程要执行的任务,每天两点判断下 正在推送的=0 ,正在移动的=0,则将文件从目录中转移到临时文件夹中
    设置临时文件夹的目的是放置误删,可找回,临时文件夹的周期是7天一删
    """
    print("定时器任务开始工作")
    global red
    global rs_video_num
    global re_video_move_num
    moving = red.get(re_video_move_num)
    trmping = red.get(rs_video_num)
    if not moving is None and  moving == b'0' and not trmping is None and trmping == b'0':
        print("开始删除文件")
        for root, dirs, files in os.walk(videoFrom):
            for file in files:
                source_file_path = os.path.join(root, file)
                target_file_path = os.path.join(videoDead, file)
                shutil.move(source_file_path, target_file_path)

def openSchedule():
    #schedule.every().day.at("02:00").do(job)
    schedule.every(30).seconds().do(job())
    print("开启定时器")
    while True:
        # 运行待处理的调度任务
        schedule.run_pending()
        # 等待一段时间
        time.sleep(1)
 # 创建一个线程对象,开始定时器任务
thread = threading.Thread(target=job())

# 启动线程
thread.start()

"""
定时器删除文件结束-------------------
"""

"""
迁移任务开始-------------------
"""

# 根据redis中拉取的 正则文件名,从指定目录中找到 真实的文件名
def getAllFiles(dir: str, regFile: str):
    regFile = r"{}".format(regFile)  # 构造新字符串,防止转义
    flv = None  # 声明返回对象
    allFiles = []
    for root, dirs, files in os.walk(dir):
        for fileFullName in files:
            if len(re.findall(regFile, fileFullName)) > 0:  # 进行正则匹配一下,如果文件名称能匹配成功,返回的符合的数组长度 >0
                # continue  # 中断循环,已经找到目标文件
                allFiles.append(fileFullName)

    return allFiles


'''
1. 一分钟一次循环,从reids中的key = 中的尾部获取一个正则文件名
2. 从指定目录下找到所有的正则匹配到的文件名返回.
3. 移动对应的文件到指定目录中
4. redis的list中删除指定的key
'''
# todo 其实有问题,如果脚本挂掉了,但是从redis中消费的值已经没了,这就导致该文件实际上丢了,所以要
while True:
    tempReg = red.lindex(rs_reg_key, -1)  # 从队列尾部获取一个值
    if tempReg == None:
        print("获取为空,休眠一段时间继续工作")
        time.sleep(3)  # 休眠一段时间继续找
        continue
    else:
        regFlvName = tempReg.decode()  # 由bytes 转成字符串
        print("获取文件名称,执行转移视频工作" + regFlvName)
        files = getAllFiles(videoFrom, regFlvName)  # 从指定目录下获取指定的文件组
        # 可能会出现 ,redis中有找到 正则文件名,但是真实文件不存在,可能在删除redis时网络不稳定
        if len(files) > 0:
            print("找到模糊匹配的文件".format(len(files)))
            for file in files:  # py中冒号代表一块代码域的开始,跟java中{}功能相似 i是元素索引相当于java fori循环
                realFile = videoFrom + "\\" + file
                if os.path.exists(realFile):
                    red.incr(re_video_move_num)
                    print("开始转移文件{}".format(file))
                    shutil.copy(realFile, videoTo)
                    red.decr(re_video_move_num)
                else:
                    print(f"头盔视频文件: {realFile}不存在,未执行迁移操作!")
                    print("头盔视频文件: {}不存在,未执行迁移操作!".format(realFile))
        else:
                print("未找到正则匹配文件\n---------------------------")
        #    lrem = red.lrem(rs_reg_key, 1, tempReg) #todo从list中删除指定的值
    time.sleep(10)  # 休眠一段时间继续找


"""
迁移任务结束-------------------
"""