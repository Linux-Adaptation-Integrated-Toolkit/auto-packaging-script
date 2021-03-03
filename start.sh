#!/bin/bash
#打开bash扩展支持
shopt -s extglob

HERE=$(dirname $(readlink -f "$0"))
XMLFILE=1.xml
archlibdir=$(dpkg-architecture -qDEB_BUILD_GNU_TYPE)

create () {
cat > opt/apps/$package/info <<EOF
 {
	 "appid": "$package",
	 "name": "$source",
	 "version": "$version",
	 "arch": ["amd64","arm64","mips64el"],
	 "permissions": {
	     "autostart": false,
	     "notification": false,
	     "trayicon": false,
	     "clipboard": false,
	     "account": false,
	     "bluetooth": false,
	     "camera": false,
	     "audio_record": false,
	     "installed_apps": false
   }
 }
EOF
}

daozhi() {
	homepagename=`echo $1 | awk -F "//" '{print $2}' | awk -F "/" '{print $1}'`
	#要将$a分割开，先存储旧的分隔符
	OLD_IFS="$IFS"
	#设置分隔符
	IFS="." 
	#如下会自动分隔
	arr=($homepagename)
	#恢复原来的分隔符
	IFS="$OLD_IFS"
	#倒置数组
	str=""
	for i in ${arr[@]};do
		str=$i"."$str
	done
	echo "倒置名$str"
	urlex=${str:0:${#str}-1}
}

a=0
for i in `cat ${HERE}/${XMLFILE} | grep row | awk '{print $1}'`
do
  a=$(($a+1))
#初始化变量
BIN=bin

#0,未开始；1,全部失败；2,虚包成功，实包失败；3,全部成功
mode=`echo $i | awk -F 'mode>' '{print $2}'|awk -F '<' '{print $1}'`
if [ $mode -ne 0 ];then
   continue
else
####################################
#1.解析xml，获取软件名。解析apt show，获取版本，分类，官网和描述
####################################
#解析xml
source=$(echo $i | awk -F 'source>' '{print $2}' | awk -F '<' '{print $1}')
binary=$(echo $i | awk -F 'binary>' '{print $2}' | awk -F '<' '{print $1}')
#创建工作目录
mkdir -p $source
#解析apt show
apt show $source > ${HERE}/${source}/1.txt
version=`cat ${HERE}/${source}/1.txt | grep Version: | awk '{print $2}'`
section=`cat ${HERE}/${source}/1.txt | grep Section: | awk '{print $2}'`
homepage=`cat ${HERE}/${source}/1.txt | grep Homepage: | awk '{print $2}'`

if [ ! `echo $homepage | awk -F "//" '{print $2}' | awk -F "/" '{print $2}'` ];then
	daozhi $homepage
	package=$urlex
else
	daozhi $homepage
	homepagename1=`echo $homepage | awk -F "//" '{print $2}'`
	OLD_IFS=$IFS
	IFS="/"
	arr1=(${homepagename1})
	IFS="$OLD_IFS"
	str2=""
	for((i=1; i<=${#arr1[*]}; i++))
	do
		if [ $i -ne ${#arr1[*]} ];then
		str2=$str2"."${arr1[$i]}
		fi
	done
	package=$urlex$str2
fi

echo 第$a个软件：源码：$source
echo 第$a个软件：包名：$package
echo 第$a个软件：版本：$version
echo ================================================================

architecture=$(dpkg-architecture -qDEB_HOST_ARCH)
echo 架构: $architecture  


####################################
#2.同时生成虚包和进行编译打包
####################################
####生成虚包
#------------------------------------------------------------------------
#进入工作目录，开始工作
cd $HERE/$source
echo "开始构建x包"
mkdir -p $HERE/$source/xubao/DEBIAN xubao/opt/apps/$package/{files,entries}
cat>$HERE/$source/xubao/DEBIAN/control<<EOF
Package: $package
Version: $version
Architecture: $architecture
Section: $section
Maintainer: zhaozhen wanweiyang <zhaozhen@uniontech.com>
Depends: $source
Homepage: https://gitee.com/deepin-opensource
Description: 欢迎使用$source
EOF

cd $HERE/$source/xubao && create
cd $HERE/$source
dpkg-deb -b $HERE/$source/xubao ${package}_${version}_${architecture}_x.deb
#scp ${package}_${version}_${architecture}_x.deb root@10.10.58.248:~/xubao
echo "x包构建完成"

####编译安装
echo "开始构建s包"
apt source $source
#进入源码目录

for dir in `ls -l |grep "^d" |awk '{print $9}'`
do
		#echo $SOURCEDIR
	  cd $HERE/$source/$dir
	  if [ -d "debian" ];then
			SOURCEDIR=$HERE/$source/$dir
	  fi
		cd $HERE/$source
done
cd $SOURCEDIR
touch $source.log
sudo apt -y build-dep .
dpkg-buildpackage -us -uc -b >> ../"${source}_build_log.txt"

#返回工程目录
cd $HERE/$source/
origindeb=`find $HERE/$source -name "${source}_*.deb"`
dpkg-deb -R $origindeb $HERE/$source/b
mkdir -p $HERE/$source/b/opt/apps/$package/{entries,files}
mv $HERE/$source/b/usr/*  $HERE/$source/b/opt/apps/$package/files
cp -r $HERE/$source/b/opt/apps/$package/files/share/* $HERE/$source/b/opt/apps/$package/entries

if [ -d "${HERE}/$source/b/opt/apps/$package/files/games" ]; then
    BIN=games
fi

#寻找desktop，修改第一个，剩下的删掉，然后改名
desktopnum=0
for file in `find $HERE/$source/b/opt/apps/$package/entries/applications -name "*.desktop"`
do
  desktoplist[$desktopnum]=$file
  ((desktopnum++))
done

#如果只有一个desktop文件就修改Exec
if [ $desktopnum -eq 1 ]; then
  packagedesktop=$HERE/$source/b/opt/apps/$package/entries/applications/${package}.desktop
  mv ${desktoplist[0]} ${packagedesktop}
  echo "修改${desktoplist[0]}文件  成为${packagedesktop}文件"
  sed -i "s#Name=.*#Name=$source#g" ${packagedesktop} 
  echo "修改${packagedesktop}文件::::Name=$source-----------"
  sed -i "s#TryExec=.*#TryExec=/opt/apps/$package/files/$BIN/$source.sh#g" ${packagedesktop} 
  sed -i "s#Exec=.*#Exec=/opt/apps/$package/files/$BIN/$source.sh U%#g" ${packagedesktop}

#如果有多个desktop，只修改第一个，然后删除其他的desktop
else
	packagedesktop=$HERE/$source/b/opt/apps/$package/entries/applications/${package}.desktop
	packagedesktop_name=${package}.desktop
        mv ${desktoplist[0]} ${packagedesktop}
        echo "修改${desktoplist[0]}文件  成为${packagedesktop}文件"
	sed -i "s#Name=.*#Name=$source#g" ${packagedesktop}
	sed -i "s#TryExec=.*#TryExec=/opt/apps/$package/files/$BIN/$source.sh#g" ${packagedesktop}
	sed -i "s#Exec=.*#Exec=/opt/apps/$package/files/$BIN/$source.sh U%#g" ${packagedesktop}
	cp -n ${packagedesktop} $HERE/$source/b/opt/apps/$package/entries/applications/
	(cd $HERE/$source/b/opt/apps/$package/entries/applications && rm -rf !($packagedesktop_name))
fi

###########创建可执行程序的.sh文件############################# 
touch $HERE/$source/b/opt/apps/$package/files/$BIN/$source.sh

echo "export LD_LIBRARY_PATH='/opt/apps/$package/files/lib/:/opt/apps/$package/files/lib/${archlibdir}'">> $HERE/$source/b/opt/apps/$package/files/$BIN/$source.sh
if [ -z "${binary}" ];then
	echo "/opt/apps/$package/files/${BIN}/${source}" >> $HERE/$source/b/opt/apps/$package/files/$BIN/$source.sh
else
	echo "/opt/apps/$package/files/${BIN}/${binary}" >> $HERE/$source/b/opt/apps/$package/files/$BIN/$source.sh
fi

chmod +x $HERE/$source/b/opt/apps/$package/files/$BIN/$source.sh
###########创建info文件#################
cd $HERE/$source/b && create

###########修改control文件###############
 sed -i "s#Package:.*#Package: $package#g" $HERE/$source/b/DEBIAN/control
 cd $HERE/$source/b/DEBIAN && rm -fr !(control)

#################打包#####################
cd $HERE/$source && dpkg-deb -b $HERE/$source/b ${package}_${version}_${architecture}_s.deb

if [ -f $HERE/$source/${package}_${version}_${architecture}_s.deb ];then
	sed -i "s#<row><source>$source</source><mode>0</mode>#<row><source>$source</source><mode>3</mode> #g" ${HERE}/${XMLFILE}
	echo "s包构建完成" | tee -a ${LOG}
	if [ ! -f $HERE/$source/b/opt/apps/${package}/files/${BIN}/${source} ];then
		sed -i "s#<row><source>$source</source><mode>3</mode>#<row><source>$source</source><mode>4</mode>#g" ${HERE}/${XMLFILE}
	fi
elif [ -f $HERE/$source/${package}_${version}_${architecture}_x.deb ];then
	sed -i "s#<row><source>$source</source><mode>0</mode>#<row><source>$source</source><mode>2</mode>#g" ${HERE}/${XMLFILE}
	echo "s包构建失败,x包构建成功" | tee -a ${LOG}
else
	sed -i "s#<row><source>$source</source><mode>0</mode>#<row><source>$source</source><mode>1</mode>#g" ${HERE}/${XMLFILE}
	echo "没有软件包构建成功" | tee -a ${LOG}
fi
#0,未开始；1,全部失败；2,虚包成功，实包失败；3,全部成功;4,全部成功，但二进制文件不对应或不存在
#scp $HERE/$package_$version_$architecture_s.deb 
#-----------------------------over------------------------------
echo 工作完成，离开工作目录
fi
cd $HERE
sleep 5
done
