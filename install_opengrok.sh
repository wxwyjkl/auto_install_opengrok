source common.sh

OPENJDK_VERSION=22

TOMCAT_VERSION=10.1.41
# Ubuntu24.10不支持opengrok最新版本1.13.24，会在访问http://localhost:8080/source时报404
OPENGROK_VERSION=1.12.28

DOWNLOAD_DIR=./downloads

OPENGROK_INSTALL_DIR=~/programs
TOMCAT_INSTALL_DIR=~/programs
TOMCAT_USER=$USER

for arg in "$@"; do
  case $arg in
    -r)
      uninstall=true
      shift
      ;;
    -i)
      shift
      OPENGROK_INSTALL_DIR=$1
      TOMCAT_INSTALL_DIR=$1
      ;;
    -h)
      logi "说明："

      exit 0
  esac
done

#=====================
# Install opengrok

function install_openjdk() {
    sudo apt install openjdk-$OPENJDK_VERSION-jdk
}

# 安装ctags，作用主要是扫描指定的源文件，找出其中所包含的语法元素，并将找到的相关内容记录下来。
function install_ctags() {
    log "Install universal-ctags"
    sudo apt remove ctags -y
    sudo apt autoremove 
    sudo apt install universal-ctags -y
}

function uninstall_ctags() {
    log "Uninstall universal-ctags"
    sudo apt remove universal-ctags -y
    sudo apt autoremove
}

function install_tomcat() {
    log "Install tomcat ($TOMCAT_VERSION)"
    mkdir -p $TOMCAT_INSTALL_DIR
    ls -al $TOMCAT_INSTALL_DIR

    sudo systemctl status tomcat --no-pager 2>&1>/dev/null
    if [ $? -eq 0 ];then
        sudo systemctl stop tomcat
    fi

    logi "Tomcat user: "$TOMCAT_USER
    if [ "$TOMCAT_USER" != "$USER" ];then
        sudo rm -rf $TOMCAT_INSTALL_DIR/tomcat
        if id -u "tomcat" >/dev/null 2>&1; then
            logw "User tomcat already exsits, delete!"
            sudo userdel -r tomcat
        fi

        logi "Add user tomcat."
        sudo useradd -m -U -d $TOMCAT_INSTALL_DIR/tomcat -s /bin/false tomcat
    else
        sudo mkdir -p $TOMCAT_INSTALL_DIR/tomcat
    fi
    
    download https://dlcdn.apache.org/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz
    logi "Install tomcat to "$TOMCAT_INSTALL_DIR/tomcat
    sudo tar -xzf ${DOWNLOAD_DIR}/apache-tomcat-${TOMCAT_VERSION}.tar.gz -C $TOMCAT_INSTALL_DIR/tomcat --strip-components=1

    sudo chown $TOMCAT_USER: -R $TOMCAT_INSTALL_DIR/tomcat
    sudo chmod u+x $TOMCAT_INSTALL_DIR/tomcat/bin

    # 配置tomcat系统服务
    tomcat_install_dir_=${TOMCAT_INSTALL_DIR//\//\\/}
    sed "s/\$TOMCAT_INSTALL_DIR/$tomcat_install_dir_/g; s/\$USER/$TOMCAT_USER/g; s/\$GROUP/$TOMCAT_USER/g; s/\$OPENJDK_VERSION/$OPENJDK_VERSION/g; s/\$TOMCAT_VERSION/$TOMCAT_VERSION/g;" \
        prebuilts/tomcat/tomcat.service > $DOWNLOAD_DIR/tomcat.service
    echo "Add tomcat.service config: prebuilts/tomcat/tomcat.service -> /etc/systemd/system/tomcat.service"
    sudo cp $DOWNLOAD_DIR/tomcat.service /etc/systemd/system/tomcat.service

    logi "Restart systemd..."
    sudo systemctl daemon-reload
    logi "Startup tomcat service..."
    sudo systemctl restart tomcat
    echo
    sudo systemctl status tomcat --no-pager
    echo
    if [ $? -eq 0 ];then
        logi "Tomcat启动成功，可通过浏览器访问： http://localhost:8080"
        read -p "是否将tomcat配置为开机启动(y/n)？" tomcat_auto_start
        if [ "$tomcat_auto_start" == "y" ];then
            sudo systemctl enable tomcat
        fi
    else
        loge "Tomcat 启动失败！"
    fi
}

function uninstall_tomcat() {
    log "Uninstall tomcat."
    sudo systemctl status tomcat --no-pager 2>&1>/dev/null
    if [ $? -eq 0 ];then
        logi "Stop tomcat service."
        sudo systemctl stop tomcat
    fi
    logi "Disable systemctl tomcat."
    sudo systemctl disable tomcat
    logi "Delete /etc/systemd/system/tomcat.service"
    sudo rm -rf /etc/systemd/system/tomcat.service
    logi "Systemctl daemon-reload"
    sudo systemctl daemon-reload

    if [ "$TOMCAT_USER" != "$USER" ];then
        if id -u "tomcat" >/dev/null 2>&1; then
            logw "Delete tomcat user: "$TOMCAT_USER
            sudo userdel -r tomcat
        fi
    fi

    logi "Delete tomcat install dir: "$TOMCAT_INSTALL_DIR/tomcat
    sudo rm -rf $TOMCAT_INSTALL_DIR/tomcat
}

function install_opengrok() {
    mkdir ~/.auto_install_opengrok
    echo $OPENGROK_INSTALL_DIR > ~/.auto_install_opengrok/install_opengrok_dir
    echo $TOMCAT_INSTALL_DIR > ~/.auto_install_opengrok/install_tomcat_dir

    install_openjdk
    install_ctags
    install_tomcat

    # 参考：https://github.com/oracle/opengrok/wiki/How-to-setup-OpenGrok
    log "Install opengrok ($OPENGROK_VERSION)"
    download https://github.com/oracle/opengrok/releases/download/$OPENGROK_VERSION/opengrok-${OPENGROK_VERSION}.tar.gz

    if [ -d $OPENGROK_INSTALL_DIR/opengrok ];then
        read -p "$OPENGROK_INSTALL_DIR/opengrok 已存在，是否删除(y/n)？" delete_opengrok_dir
        if [ $delete_opengrok_dir == "y" ];then
            rm -rf $OPENGROK_INSTALL_DIR/opengrok
        fi
    fi
   
    mkdir -p $OPENGROK_INSTALL_DIR/opengrok/{src,data,dist,etc,log}
    logi "Install opengrok to "$OPENGROK_INSTALL_DIR/opengrok
    tar -C $OPENGROK_INSTALL_DIR/opengrok/dist --strip-components=1 -xzf $DOWNLOAD_DIR/opengrok-${OPENGROK_VERSION}.tar.gz

    cp $OPENGROK_INSTALL_DIR/opengrok/dist/doc/logging.properties $OPENGROK_INSTALL_DIR/opengrok/etc

    logi "Install opengrok tools. (python venv)"
    cd $OPENGROK_INSTALL_DIR/opengrok/dist/tools
    python3 -m venv opengrok-tools
    source ./opengrok-tools/bin/activate
    python3 -m pip install opengrok-tools.tar.gz

    local opengrok_deploy_cmd="opengrok-deploy \
        -c $OPENGROK_INSTALL_DIR/opengrok/etc/configuration.xml \
        $OPENGROK_INSTALL_DIR/opengrok/dist/lib/source.war \
        ${TOMCAT_INSTALL_DIR}/tomcat/webapps"
    logi "Run: $opengrok_deploy_cmd"
    $opengrok_deploy_cmd

    logi "Restart tomcat service."
    sudo systemctl restart tomcat

    local opengrok_index_cmd="opengrok-indexer \
        -J=-Xmx8g \
        -J=-Djava.util.logging.config.file=$OPENGROK_INSTALL_DIR/opengrok/etc/logging.properties \
        -a $OPENGROK_INSTALL_DIR/opengrok/dist/lib/opengrok.jar -- \
        -c /usr/bin/ctags \
        -s $OPENGROK_INSTALL_DIR/opengrok/src \
        -d $OPENGROK_INSTALL_DIR/opengrok/data \
        -P -W $OPENGROK_INSTALL_DIR/opengrok/etc/configuration.xml \
        -U http://localhost:8080/source \
        -P --progress -v"
    opengrok_index_cmd=`echo $opengrok_index_cmd | tr -s ' '`
    logi "Run: $opengrok_index_cmd"
    $opengrok_index_cmd

    echo
    echo "=========================="
    logi "使用说明："
    echo "=========================="
    echo
    echo "1. 添加源码（创建链接目录即可）"
    echo -e "\033[32m    ln -s <源码路径> $OPENGROK_INSTALL_DIR/opengrok/src\033[0m"
    echo
    echo "2. 执行opengrok-indexer命令更新源码索引（android源码较大，可能需要等待30分钟以上），两种方式均可:"
    echo
    echo "  1) Opengrok-tools命令（需要先进入python vevn环境）:"
    echo -e "\033[32m    source $OPENGROK_INSTALL_DIR/opengrok/dist/tools/opengrok-tools/bin/activate\033[0m"
    echo -e "\033[32m    $opengrok_index_cmd\033[0m"
    echo -e "\033[32m    deactivate\033[0m"
    echo
    echo "  2) Java命令："
    java_index_cmd="java \
        -Xmx8g \
        -Djava.util.logging.config.file=$OPENGROK_INSTALL_DIR/opengrok/etc/logging.properties \
        -jar $OPENGROK_INSTALL_DIR/opengrok/dist/lib/opengrok.jar \
        -c /usr/bin/ctags \
        -s $OPENGROK_INSTALL_DIR/opengrok/src \
        -d $OPENGROK_INSTALL_DIR/opengrok/data \
        -W $OPENGROK_INSTALL_DIR/opengrok/etc/configuration.xml \
        -U "http://localhost:8080/source" \
        -P --progress -v"
    java_index_cmd=`echo $java_index_cmd | tr -s ' '`
    echo -e "\033[32m    $java_index_cmd\033[0m"
    echo
    echo "查看opengrok工具使用说明："
    echo "  $ java -jar $OPENGROK_INSTALL_DIR/opengrok/dist/lib/opengrok.jar -h"
    echo
    echo "3. 使用浏览器访问本地opengrok服务： http://localhost:8080/source/"
    echo
    echo "注意：每次代码有变动时都需要执行第2步的命令来更新索引，否则opengrok上显示的仍然是修改前的代码，可以考虑配置一个定时任务来更新代码索引，对于Android代码，由于更新索引耗时比较久，建议每日凌晨定时更新即可。"
}

function uninstall_opengrok() {
    log "Uninstall opengrok."

    OPENGROK_INSTALL_DIR=`cat ~/.auto_install_opengrok/install_opengrok_dir`
    TOMCAT_INSTALL_DIR=`cat ~/.auto_install_opengrok/install_tomcat_dir`
    rm -rf ~/.auto_install_opengrok

    logi "Delete opengrok install dir: "$OPENGROK_INSTALL_DIR/opengrok
    sudo rm -rf $OPENGROK_INSTALL_DIR/opengrok
    logi "Delete tomcat opengrok war: "$TOMCAT_INSTALL_DIR/tomcat/webapps/source.war
    sudo rm -rf $TOMCAT_INSTALL_DIR/tomcat/webapps/source.war
    sudo rm -rf $TOMCAT_INSTALL_DIR/tomcat/webapps/source

    uninstall_tomcat
    uninstall_ctags
}


if [ "$uninstall" == "true" ];then
    uninstall_opengrok
else
    install_opengrok
fi