# icp_xinxi
icp信息收集脚本，本质上就是几个项目用python和shell脚本糅合在一起了，为啥会想要写这个脚本，因为有些项目和工具在爬取icp的小程序和APP的时候会有些问题。所以就写了一个脚本。然后由于笔者近期在学习信息收集，所以就加上了其他部分。整个脚本的过程是：

```shell
icp-->会爬取icp上的web和app还有小程序的信息-->调用oneforall进行子域名收集-->然后将收集的子域名使用曾哥的项目进行探活-->将探活的子域名使用masscan进行端口扫描-->扫描的结果再用dirsearch进行目录扫描-->生成200和403两种状态码的结果-->保存到icp的目录下
```

调用的项目的原链接：

```shell
dirsearch：https://github.com/maurosoria/dirsearch
icp查询：https://github.com/HG-ha/ICP_Query
oneforall：https://github.com/shmilylty/OneForAll
Web-SurvivalScan：https://github.com/AabyssZG/Web-SurvivalScan
```



## 环境部署

### icp_query部署

```shell
docker run -d -p 16181 yiminger/ymicp
```

使用docker直接进行拉取，然后根据你的本地开放的端口修改icp目录下的`icp.py`

![image-20250910193615148](https://cdn.jsdelivr.net/gh/Yat-ming666/PicGoCDN/img/20250910193615181.png)

比如说这里我的是32768，下图红框中的端口就要进行对应的修改：

![image-20250910193848228](https://cdn.jsdelivr.net/gh/Yat-ming666/PicGoCDN/img/20250910193848314.png)

然后分别进入dirsearch和Oneforall，还有icp下的Webscan进行python的的环境安装，这里都用的python的虚拟环境

```shell
python3 -m venv venv
source venv/bin/activate

#这里有一个需要注意的点就是你的虚拟目录要和我的一样都是venv，因为脚本里面写死了。。。

进入每个项目的虚拟目录之后，pip3 install -r xxx.txt
正常安装即可
每个项目安装之后，需要退出虚拟环境，保证环境的独立性，退出的命令是：
deactivate
```

![image-20250910194206873](https://cdn.jsdelivr.net/gh/Yat-ming666/PicGoCDN/img/20250910194206912.png)

```shell
#进到icp目录给予这几个脚本执行权限
chmod +x oneforall.sh 
chmod +x tanhuo.sh 
chmod +x masscan_scan.sh 
chmod +x dir.sh
```

然后就可以啦~
