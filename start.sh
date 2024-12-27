#!/bin/bash

RED='\033[0;91m'
GREEN='\033[0;92m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;96m'
WHITE='\033[0;37m'
RESET='\033[0m'
yellow() {
  echo -e "${YELLOW}$1${RESET}"
}
green() {
  echo -e "${GREEN}$1${RESET}"
}
red() {
  echo -e "${RED}$1${RESET}"
}
installpath="$HOME"
if [[ -e "$installpath/serv00-play" ]]; then 
  source ${installpath}/serv00-play/utils.sh
fi

PS3="请选择(输入0退出): "
install(){
  cd ${installpath}
  if [ -d serv00-play ]; then
    cd "serv00-play"
    git stash
    if git pull; then
      echo "更新完毕"
     #重新给各个脚本赋权限
      chmod +x ./start.sh
      chmod +x ./keepalive.sh
      chmod +x ${installpath}/serv00-play/ssl/cronSSL.sh
      red "请重新启动脚本!"
      exit 0
    fi
  fi
  
  cd ${installpath}
  echo "正在安装..."
  if ! git clone https://github.com/jilin6654/serv00-play.git; then
    echo -e "${RED}安装失败!${RESET}"
    exit 1;
  fi
  echo -e "${YELLOW}安装成功${RESET}"
}




setConfig(){
  cd ${installpath}/serv00-play/

  if [ -f config.json ]; then
    echo "目前已有配置:"
    config_content=$(cat config.json)
    echo $config_content
    read -p "是否修改? [y/n] [y]:" input
    input=${input:-y}
    if [ "$input" != "y" ]; then
      return
    fi
  fi
  createConfigFile
}

createConfigFile(){
  
  echo "选择你要保活的项目（可多选，用空格分隔）:"
  echo "1. sun-panel "
  echo "2. alist"
  echo "3. webssh"
  item=()

  read -p "请选择: " choices
  choices=($choices)  

  if [[ "${choices[@]}" =~ "88" && ${#choices[@]} -gt 1 ]]; then
     red "选择出现了矛盾项，请重新选择!"
     return 1
  fi

  #过滤重复
  choices=($(echo "${choices[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

  # 根据选择来询问对应的配置
  for choice in "${choices[@]}"; do
    case "$choice" in
    1) 
       item+=("sun-panel")
       ;;
    2)
      item+=("alist")
      ;;
    3) 
      item+=("webssh")
      ;;
    *)
       echo "无效选择"
       return 1
       ;;
   esac
done

  json_content="{\n"
  json_content+="   \"item\": [\n"
  
  for item in "${item[@]}"; do
      json_content+="      \"$item\","
  done

  # 删除最后一个逗号并换行
  json_content="${json_content%,}\n"
  json_content+="   ],\n"

  if [ "$num" = "4" ]; then
    json_content+="   \"chktime\": \"null\""
    json_content+="}\n"
    printf "$json_content" > ./config.json
    echo -e "${YELLOW} 设置完成! ${RESET} "
    delCron
    return
  fi

  read -p "配置保活检查的时间间隔(单位分钟，默认1分钟):" tm
  tm=${tm:-"1"}

  json_content+="   \"chktime\": \"$tm\","

  read -p "是否需要配置消息推送? [y/n] [n]:" input
  input=${input:-n}

  if [ "${input}" == "y" ]; then
    json_content+="\n"

    echo "选择要推送的app:"
    echo "1) Telegram "
    echo "2) 微信 "
    echo "3) 以上皆是"

    read -p "请选择:" sendtype
    
    if [ "$sendtype" == "1" ]; then
      writeTG
   elif [ "$sendtype" == "2" ]; then
      writeWX
   elif [ "$sendtype" == "3" ]; then
      writeTG
      writeWX
   else
    echo "无效选择"
    return
   fi
  else 
    sendtype=${sendtype:-"null"}
 fi
  json_content+="\n \"sendtype\": $sendtype \n"
  json_content+="}\n"
  
  # 使用 printf 生成文件
  printf "$json_content" > ./config.json
  addCron $tm
  chmod +x ${installpath}/serv00-play/keepalive.sh
  echo -e "${YELLOW} 设置完成! ${RESET} "

}

backupConfig(){
  local filename=$1
  if [[ -e "$filename" ]]; then
    if [[ "$filename" =~ ".json" ]]; then
      local basename=${filename%.json}
      mv $filename $basename.bak
    fi
  fi
}

restoreConfig(){
  local filename=$1
  if [[ -e "$filename" ]]; then
    if [[ "$filename" =~ ".bak" ]]; then
      local basename=${filename%.bak}
      mv $filename $basename.json
    fi
  fi
}



killUserProc(){
  local user=$(whoami)
  pkill -kill -u $user
}

ImageRecovery(){
  cd ${installpath}/backups/local
  # 定义一个关联数组
  declare -A snapshot_paths

  # 遍历每个符号链接，并将文件夹名称及真实路径保存到数组中
  while read -r line; do
    # 提取文件夹名称和对应的真实路径
    folder=$(echo "$line" | awk '{print $9}')
    real_path=$(echo "$line" | awk '{print $11}')
    
    # 将文件夹名称和真实路径存入数组
    snapshot_paths["$folder"]="$real_path"
  done < <(ls -trl | grep -F "lrwxr")

  size=${#snapshot_paths[@]}
  sorted_keys=($(echo "${!snapshot_paths[@]}" | tr ' ' '\n' | sort -r))
  if [ $size -eq 0 ]; then
    echo "未有备份快照!"
    return   
  fi
  echo  "选择你需要恢复的内容:"
  echo "1. 完整快照恢复 "
  echo "2. 恢复某个文件或目录"
  read -p "请选择:" input

  if [ "$input" = "1" ]; then
      local i=1
      declare -a folders
      for folder in "${sorted_keys[@]}"; do
        echo "${i}. ${folder} "
        i=$((i+1))
      done
      retries=3
      while [ $retries -gt 0 ]; do
        read -p  "请选择恢复到哪一天(序号)？" input
         # 检查输入是否有效
         if [[ $input =~ ^[0-9]+$ ]] && [ "$input" -gt 0 ] && [ "$input" -le $size ]; then
          # 输入有效，退出循环
           targetFolder="${sorted_keys[@]:$input-1:1}"
           echo "你选择的恢复日期是：${targetFolder}"
           break
         else
           # 输入无效，减少重试次数
            retries=$((retries-1))
            echo "输入有误，请重新输入！你还有 $retries 次机会。"
         fi
         if [ $retries -eq 0 ]; then
           echo "输入错误次数过多，操作已取消。"
           return  
         fi
      done
      killUserProc
      srcpath=${snapshot_paths["${targetFolder}"]}
      #echo "srcpath:$srcpath"
       rm -rf ~/* > /dev/null 2>&1  
       rsync -a $srcpath/ ~/  2>/dev/null  
      yellow "快照恢复完成!"
      return
  elif [ "$input" = "2" ]; then
      declare -A foundArr
      read -p "输入你要恢复到文件或目录:" infile
      
      for folder in "${!snapshot_paths[@]}"; do
          path="${snapshot_paths[$folder]}"
         results=$(find "${path}" -name "$infile" 2>/dev/null)
        # echo "111results:|$results|"     
         if [[ -n "$results" ]]; then
          #echo "put |$results| to folder:$folder"
          foundArr["$folder"]="$results"
         fi
      done
      local i=1
      sortedFoundArr=($(echo "${!foundArr[@]}" | tr ' ' '\n' | sort -r))
      declare -A indexPathArr
      for folder in "${sortedFoundArr[@]}"; do
        echo "$i. $folder:"
        results="${foundArr[${folder}]}"
        IFS=$'\n' read -r -d '' -a paths <<< "$results"
        local j=1
        for path in "${paths[@]}"; do
          indexPathArr["$i"."$j"]="$path"
          echo "  $j. $path"
          
          j=$((j+1))
        done
        i=$((i+1))
      done
      
      while [ true ]; do
        read -p "输入要恢复的文件序号，格式:日期序号.文件序号, 多个以逗号分隔.(如输入 1.2,3.2)[按enter返回]:" input
        regex='^([0-9]+\.[0-9]+)(,[0-9]+\.[0-9]+)*$'

        if [ -z "$input" ]; then
            return
        fi
      
        if [[ "$input" =~ $regex ]]; then
          declare -a pairNos
          declare -a fileNos 
          IFS=',' read -r -a pairNos <<< "$input"

          echo "请选择文件恢复的目标路径:" 
          echo "1.原路返回 "
          echo "2.${installpath}/restore "
          read -p "请选择:" targetDir

          if [[ "$targetDir" != "1" ]] && [[ "$targetDir" != "2" ]];then
              red "无效输入!"
              return
          fi

          for pairNo in "${pairNos[@]}"; do
            srcpath="${indexPathArr[$pairNo]}"

            if [ "$targetDir" = "1" ]; then
              local user=$(whoami)
              targetPath=${srcpath#*${user}}
              if [ -d $srcpath ]; then
                 targetPath=${targetPath%/*}
              fi
              echo "cp -r $srcpath $HOME/$targetPath"
              cp -r ${srcpath} $HOME/${targetPath}
              
            elif [ "$targetDir" = "2" ]; then
              targetPath="${installpath}/restore"
              if [ ! -e "$targetPath" ]; then
                mkdir -p "$targetPath" 
              fi
              cp -r $srcpath $targetPath/
            fi  
          done
          green "完成文件恢复"
          
        else
          red "输入格式不对，请重新输入！"
        fi
      done
  fi
 
}


InitServer(){
  read -p "$(red "将初始化帐号系统，要继续？[y/n] [n]:")" input
  input=${input:-n}
  read -p "是否保留用户配置？[y/n] [y]:" saveProfile
  saveProfile=${saveProfile:-y}

  if [[ "$input" == "y" ]] || [[ "$input" == "Y" ]]; then
    cleanCron
    green "清理进程中..."
    killUserProc
    green "清理磁盘中..."
    if [[ "$saveProfile" = "y" ]] || [[ "$saveProfile" = "Y" ]]; then
      rm -rf ~/* 2>/dev/null
    else
      rm -rf ~/* ~/.* 2>/dev/null
    fi
    cleanPort
    yellow "初始化完毕"
    
   exit 0
  fi
}

setCnTimeZone(){
  read -p "确定设置中国上海时区? [y/n] [y]:" input
  input=${input:-y}
  
  cd ${installpath}
  if [ "$input" = "y" ]; then
    devil binexec on
    touch .profile
    cat .profile | perl ./serv00-play/mkprofile.pl > tmp_profile
    mv -f tmp_profile .profile
    
    read -p "$(yellow 设置完毕,需要重新登录才能生效，是否重新登录？[y/n] [y]:)"  input
    input=${input:-y}

    if [ "$input" = "y" ]; then
       kill -9 $PPID
    fi
  fi
  
}

setColorWord(){
  cd ${installpath}
  # 定义颜色编码
  bright_black="\033[1;90m"
  bright_red="\033[1;91m"
  bright_green="\033[1;92m"
  bright_yellow="\033[1;93m"
  bright_blue="\033[1;94m"
  bright_magenta="\033[1;95m"
  bright_cyan="\033[1;96m"
  bright_white="\033[1;97m"
  reset="\033[0m"

  # 显示颜色选项列表，并使用颜色着色
  echo -e "请选择一个颜色来输出你的签名:"
  echo -e "1) ${bright_black}明亮黑色${reset}"
  echo -e "2) ${bright_red}明亮红色${reset}"
  echo -e "3) ${bright_green}明亮绿色${reset}"
  echo -e "4) ${bright_yellow}明亮黄色${reset}"
  echo -e "5) ${bright_blue}明亮蓝色${reset}"
  echo -e "6) ${bright_magenta}明亮紫色${reset}"
  echo -e "7) ${bright_cyan}明亮青色${reset}"
  echo -e "8) ${bright_white}明亮白色${reset}"

  # 读取用户输入的选择
  read -p "请输入你的选择(1-8): " color_choice

  read -p "请输入你的大名(仅支持ascii字符):" name

  # 根据用户的选择设置颜色
  case $color_choice in
      1) color_code="90" ;; # 明亮黑色
      2) color_code="91" ;; # 明亮红色
      3) color_code="92" ;; # 明亮绿色
      4) color_code="93" ;; # 明亮黄色
      5) color_code="94" ;; # 明亮蓝色
      6) color_code="95" ;; # 明亮紫色
      7) color_code="96" ;; # 明亮青色
      8) color_code="97" ;; # 明亮白色
      *) echo "无效选择，使用默认颜色 (明亮白色)"; color_code="97" ;;
  esac
  
  if grep "chAngEYourName" .profile > /dev/null ; then
     cat .profile | grep -v "chAngEYourName" > tmp_profile
     echo "echo -e \"\033[1;${color_code}m\$(figlet \"${name}\")\033[0m\"  #chAngEYourName" >> tmp_profile
     mv -f tmp_profile .profile
  else
    echo "echo -e \"\033[1;${color_code}m\$(figlet \"${name}\")\033[0m\" #chAngEYourName" >> .profile
  fi

  read -p  "设置完毕! 重新登录看效果? [y/n] [y]:" input
  input=${input:-y}
  if [[ "$input" == "y" ]]; then
    kill -9 $PPID
  fi

}

showIP(){
  myip="$(curl -s icanhazip.com)"
  green "本机IP: $myip"
}

extract_user_and_password() {
    output=$1

    username=$(echo "$output" | grep "username:" | sed 's/.*username: //')
    password=$(echo "$output" | grep "password:" | sed 's/.*password: //')
    echo "生成用户密码如下，请谨记! 只会出现一次:"
    green "Username: $username"
    green "Password: $password"
}

update_http_port() {
   cd data || return 1
    local port=$1
    local config_file="config.json"

    if [ -z "$port" ]; then
        echo "Error: No port number provided."
        return 1
    fi
    # 使用 jq 来更新配置文件中的 http_port
    jq --argjson new_port "$port" '.scheme.http_port = $new_port' "$config_file" > tmp.$$.json && mv tmp.$$.json "$config_file"

    echo "配置文件处理完毕."

}


installAlist(){
  if ! checkInstalled "serv00-play"; then
     return 1
  fi
  cd ${installpath}/serv00-play/ || return 1
  alistpath="${installpath}/serv00-play/alist"

  if [[ ! -e "$alistpath" ]]; then
    mkdir -p $alistpath
  fi
  if [[ -d "$alistpath/data" && -e "$alistpath/alist" ]]; then 
      echo "已安装，请勿重复安装。"
      return 
  else 
      cd "alist" || return 1
      if [ ! -e "alist" ]; then
        # read -p "请输入使用密码:" password
        if ! checkDownload "alist"; then
          return 1
        fi
      fi
  fi

  loadPort 
  randomPort tcp alist
  if [[ -n "$port" ]]; then
      alist_port="$port"
  fi
  echo "正在安装alist，请等待..."
  domain=""
  webIp=""
  if ! makeWWW alist $alist_port ; then
    echo "绑定域名失败!"
    return 1
  fi
  if ! applyLE $domain $webIp; then
    echo "申请证书失败!"
    return 1
  fi
  cd $alistpath
  rt=$(chmod +x ./alist && ./alist admin random 2>&1 )
  extract_user_and_password "$rt"
  update_http_port "$alist_port"

  green "安装完毕"
  
}

startAlist(){
  alistpath="${installpath}/serv00-play/alist"
  cd $alistpath
  domain=$(jq -r ".domain" config.json)

  if [[ -d "$alistpath/data" && -e "$alistpath/alist" ]]; then 
    cd $alistpath
    echo "正在启动alist..."
    if  checkProcAlive alist; then
      echo "alist已启动，请勿重复启动!"
    else
      nohup ./alist server > /dev/null 2>&1 &
      sleep 3
      if ! checkProcAlive alist; then
        red "启动失败，请检查!"
        return 1
      else
        green "启动成功!"
        green "alist管理地址: https://$domain"
      fi
    fi
  else
    red "请先行安装再启动!"
    return     
  fi
}

stopAlist(){
  if checkProcAlive "alist"; then
     stopProc "alist"
     sleep 3
  fi
     
}

uninstallProc(){
  local path=$1
  local procname=$2

  if [ ! -e "$path" ]; then   
      red "未安装$procname!!!"
      return 1
  fi
  cd $path
  read -p "确定卸载${procname}吗? [y/n] [n]:" input
  input=${input:-n}
  if [[ "$input" == "y" ]]; then
    stopProc "$procname"
    domain=$(jq -r ".domain" config.json)
    webip=$(jq -r ".webip" config.json)
    resp=$(devil ssl www del $webIp $domain)
    resp=$(devil www del $domain --remove)
    cd ${installpath}/serv00-play
    rm -rf $path
    green "卸载完毕!"
  fi

}

uninstallAlist(){
  alistpath="${installpath}/serv00-play/alist"
  uninstallProc "$alistpath" alist
  
}

resetAdminPass(){
  alistpath="${installpath}/serv00-play/alist"
  cd $alistpath

  output=$(./alist admin random 2>&1)
  extract_user_and_password "$output"
}

alistServ(){
  if ! checkInstalled "serv00-play"; then
     return 1
  fi
  while true; do
   yellow "----------------------"
   echo "alist:"
   echo "服务状态: $(checkProcStatus alist)"
   echo "1. 安装部署alist "
   echo "2. 启动alist"
   echo "3. 停掉alist"
   echo "4. 重置admin密码"
   echo "8. 卸载alist"
   echo "9. 返回主菜单"
   echo "0. 退出脚本"
   yellow "----------------------"
   read -p "请选择:" input

   case $input in
     1) installAlist
        ;;
     2) startAlist
        ;;
     3) stopAlist
        ;;
     4) resetAdminPass
        ;;
     8) uninstallAlist
        ;;
     9)  break
        ;;
     0) exit 0
        ;;
     *)
       echo "无效选项，请重试"
      ;;
    esac
  done
  showMenu
}

declare -a indexPorts
loadIndexPorts(){
  output=$(devil port list)

  indexPorts=()
  # 解析输出内容
  index=0
  while read -r port typ opis; do
      # 跳过标题行
      if [[ "$port" =~ "Port" ]]; then
          continue
      fi
      #echo "port:$port,typ:$typ, opis:$opis"
      if [[ "$port" =~ "Brak" || "$port" =~ "No" ]]; then
          echo "未分配端口"
          return 0
      fi

      if [[ -n "$port" ]]; then
        opis=${opis:-""} 
        indexPorts[$index]="$port|$typ|$opis"
        ((index++)) 
      fi
  done <<< "$output"


}

printIndexPorts() {
  local i=1
  echo "  Port   | Type  |  Description"
  for entry in "${indexPorts[@]}"; do
    # 使用 | 作为分隔符拆分 port、typ 和 opis

    IFS='|' read -r port typ opis <<< "$entry"
    echo "${i}. $port |  $typ | $opis"
    ((i++))
  done
}


delPortMenu(){
  loadIndexPorts

  if [[ ${#indexPorts[@]} -gt 0 ]]; then
     printIndexPorts
     read -p "请选择要删除的端口记录编号(输入0删除所有端口记录, 回车返回):" number
     number=${number:-99}
     
     if [[ $number -eq 99 ]]; then
        return
     elif [[ $number -gt 3 || $number -lt 0 ]]; then
       echo "非法输入!"
       return 
     elif [[ $number -eq 0 ]]; then
       cleanPort
     else 
         idx=$((number-1))
         IFS='|' read -r port typ opis <<< ${indexPorts[$idx]}
         devil port del $typ $port  > /dev/null 2>&1
     fi
      echo "删除完毕!"
  else
     red "未有分配任何端口!"
  fi
        
}

addPortMenu(){
  echo "选择端口类型:"
  echo "1. tcp"
  echo "2. udp"
  read -p "请选择:" co

  if [[ "$co" != "1" && "$co" != "2" ]]; then
    red "非法输入"
    return 
  fi
  local type=""
  if [[ "$co" == "1" ]]; then
     type="tcp"
  else
     type="udp"
  fi
  loadPort
  read -p "请输入端口备注(如hy2，vmess，用于脚本自动获取端口):" opts
  local port=$(getPort $type $opts )
  if [[ "$port" == "failed" ]]; then
    red "分配端口失败,请重新操作!"
  else
    green "分配出来的端口是:$port"
  fi
}

portServ(){
  while true; do
  yellow "----------------------"
    echo "端口管理:"
    echo "1. 删除某条端口记录"
    echo "2. 增加一条端口记录"
    echo "9. 返回主菜单"
    echo "0. 退出脚本"
  yellow "----------------------"
    read -p "请选择:" input
    case $input in
      1) delPortMenu
        ;;
      2) addPortMenu
        ;;
      9)
        break
        ;;
      0)
        exit 0
        ;;
      *)
        echo "无效选项，请重试"
        ;;
    esac
  done
  showMenu
}

cronLE(){
  read -p "请输入定时运行的时间间隔(小时[1-23]):" tm
  tm=${tm:-""}
  if [[ -z "$tm" ]]; then
     red "时间不能为空"
     return 1
  fi   
  if [[ $tm -lt 1 || $tm -gt 23 ]]; then
    red "输入非法!"
    return 1  
  fi
  crontab -l > le.cron
  echo "0 */$tm * * * $workpath/cronSSL.sh $domain > /dev/null 2>&1 " >> le.cron
  crontab le.cron > /dev/null 2>&1 
  rm -rf le.cron
  echo "设置完毕!"
}

get_default_webip(){
      local host="$(hostname | cut -d '.' -f 1)"
      local sno=${host/s/web}
      local webIp=$(devil vhost list public | grep "$sno" | awk '{print $1}')
      echo "$webIp"
}

applyLE(){
  local domain=$1
  local webIp=$2
  workpath="${installpath}/serv00-play/ssl"
  cd "$workpath"

  if [[ -z "$domain" ]]; then
    read -p "请输入待申请证书的域名:" domain
    domain=${domain:-""}
    if [[ -z "$domain" ]]; then
      red "域名不能为空"
      return 1
    fi
  fi
  inCron="0"
  if crontab -l | grep -F "$domain" > /dev/null 2>&1 ; then
     inCron="1"
     echo "该域名已配置定时申请证书，是否删除定时配置记录，改为手动申请？[y/n] [n]:" input
     input=${input:-n}

     if [[ "$input" == "y" ]]; then
        crontab -l | grep -v "$domain" | crontab -
     fi
  fi
  if [[ -z "$webIp" ]]; then
    read -p "是否指定webip? [y/n] [n]:" input
    input=${input:-n}
    if [[ "$input" == "y" ]]; then
       read -p "请输入webip:" webIp
       if [[ -z "webIp" ]]; then
          red "webip 不能为空!!!"
          return 1
       fi
    else
      host="$(hostname | cut -d '.' -f 1)"
      sno=${host/s/web}
      webIp=$(devil vhost list public | grep "$sno" | awk '{print $1}')
    fi
  fi
  #echo "申请证书时，webip是: $webIp"
  resp=$(devil ssl www add $webIp le le $domain)
  if [[ ! "$resp" =~ .*succesfully.*$ ]]; then 
     red "申请ssl证书失败！$resp"
     if [[ "$inCron" == "0" ]]; then
        read -p "是否配置定时任务自动申请SSL证书？ [y/n] [n]:" input
        input=${input:-n}
        if [[ "$input" == "y" ]]; then
            cronLE
        fi
     fi
  else
     green "证书申请成功!"
  fi    
}

selfSSL(){
  workpath="${installpath}/serv00-play/ssl"
  cd "$workpath"

  read -p "请输入待申请证书的域名:" self_domain
  self_domain=${self_domain:-""}
  if [[ -z "$self_domain" ]]; then
     red "域名不能为空"
     return 1
  fi
  
  echo "正在生成证书..."

  cat > openssl.cnf <<EOF
    [req]
    distinguished_name = req_distinguished_name
    req_extensions = req_ext
    x509_extensions = v3_ca # For self-signed certs
    prompt = no

    [req_distinguished_name]
    C = US
    ST = ca
    L = ca
    O = ca
    OU = ca
    CN = $self_domain

    [req_ext]
    subjectAltName = @alt_names

    [v3_ca]
    subjectAltName = @alt_names

    [alt_names]
    DNS.1 = $self_domain

EOF
  openssl req -new -newkey rsa:2048 -nodes -keyout _private.key -x509 -days 3650 -out _cert.crt -config openssl.cnf -extensions v3_ca > /dev/null 2>&1 
  if [ $? -ne 0 ]; then
    echo "生成证书失败!"
    return 1
  fi

  echo "已生成证书:"
  green "_private.key"
  green "_cert.crt"

  echo "正在导入证书.."
  host="$(hostname | cut -d '.' -f 1)"
  sno=${host/s/web}
  webIp=$(devil vhost list public | grep "$sno" | awk '{print $1}')
  resp=$(devil ssl www add "$webIp" ./_cert.crt ./_private.key "$self_domain" )

  if [[ ! "$resp" =~ .*succesfully.*$ ]]; then 
     echo "导入证书失败:$resp"
     return 1
  fi

  echo "导入成功！"
  
}

domainSSLServ(){
  while true; do
    yellow "---------------------"
    echo "域名证书管理:"
    echo "1. 抢域名证书"
    echo "2. 配置自签证书"
    echo "9. 返回主菜单"
    echo "0. 退出脚本"
    yellow "---------------------"
    read -p "请选择:" input
  
    case $input in 
      1) applyLE
        ;;
      2) selfSSL
        ;;
      9) break
        ;;
      0)
         exit 0
         ;;
      *) 
        echo "无效选项，请重试"
        ;;
    esac 
 done
 showMenu
}

getUnblockIP(){
  local hostname=$(hostname)
  local host_number=$(echo "$hostname" | awk -F'[s.]' '{print $2}')
  local hosts=("cache${host_number}.serv00.com" "web${host_number}.serv00.com" "$hostname")

  yellow "----------------------------------------------"
  green "  主机名称          |      IP        |  状态"
  yellow "----------------------------------------------"
  # 遍历主机名称数组
  for host in "${hosts[@]}"; do
    # 获取 API 返回的数据
    local response=$(curl -s "https://ss.botai.us.kg/api/getip?host=$host")

    # 检查返回的结果是否包含 "not found"
    if [[ "$response" =~ "not found" ]]; then
      echo "未识别主机${host}, 请联系作者饭奇骏!"
      return
    fi
    local ip=$(echo "$response" | awk -F "|" '{print $1 }')
    local status=$(echo "$response" | awk -F "|" '{print $2 }')
    printf "%-20s | %-15s | %-10s\n" "$host" "$ip" "$status"   
  done
    
}

checkProcStatus(){
  local procname=$1
  if checkProcAlive $procname ; then
     green "运行"
  else
     red "未运行"
  fi
  
}

sunPanelServ(){
  if ! checkInstalled "serv00-play"; then
     return 1
  fi
  while true; do
    yellow "---------------------"
    echo "sun-panel:"
    echo "服务状态: $(checkProcStatus sun-panel)"
    echo "1. 安装"
    echo "2. 启动"
    echo "3. 停止"
    echo "4. 初始化密码"
    echo "8. 卸载"
    echo "9. 返回主菜单"
    echo "0. 退出脚本"
    yellow "---------------------"
    read -p "请选择:" input
    
    case $input in 
      1) installSunPanel
        ;;
      2) startSunPanel
        ;;
      3) stopSunPanel
        ;;
      4) resetSunPanelPwd
        ;;
      8) uninstallSunPanel
        ;;
      9) break
        ;;
      0) exit 0
         ;;
      *)  echo "无效选项，请重试"
        ;;
    esac 
 done
   showMenu
}

uninstallSunPanel(){
  local workdir="${installpath}/serv00-play/sunpanel"
  uninstallProc "$workdir" "sun-panel"
}

resetSunPanelPwd(){
  local exepath="${installpath}/serv00-play/sunpanel/sun-panel"
  if [[ ! -e $exepath ]]; then
     echo "未安装，请先安装!"
     return 
  fi
  read -p "确定初始化密码? [y/n][n]:" input
  input=${input:-n}

  if [[ "$input" == "y" ]]; then
     local workdir="${installpath}/serv00-play/sunpanel"
     cd $workdir
     ./sun-panel -password-reset
  fi
     
}

stopSunPanel(){
  stopProc "sun-panel"
  if checkProcAlive "sun-panel"; then
     echo "未能停止，请手动杀进程!"
  fi
 
}

installSunPanel(){
  local workdir="${installpath}/serv00-play/sunpanel"
  local exepath="${installpath}/serv00-play/sunpanel/sun-panel"
  if [[ -e $exepath ]]; then
     echo "已安装，请勿重复安装!"
     return 
  fi
  mkdir -p $workdir
  cd $workdir

  if ! checkDownload "sun-panel"; then
     return 1
  fi
  if ! checkDownload "panelweb" 1; then
     return 1
  fi
     
  if [[ ! -e "sun-panel" ]]; then
     echo "下载文件解压失败！"
     return 1
  fi
  #初始化密码，并且生成相关目录文件
  ./sun-panel -password-reset

  if [[ ! -e "conf/conf.ini" ]]; then
     echo "无配置文件生成!"
     return 1
  fi
  
  loadPort
  port=""
  randomPort "tcp" "sun-panel"
  if [ -n "$port" ]; then
     sunPanelPort=$port
  else
     echo "未输入端口!"
     return 1
  fi
  cd conf
  sed -i.bak -E "s/^http_port=[0-9]+$/http_port=${sunPanelPort}/" conf.ini
  cd ..
  
  domain=""
  webIp=""
  if ! makeWWW panel $sunPanelPort ; then
    echo "绑定域名失败!"
    return 1
  fi
  # 自定义域名时申请证书的webip可以从2个ip中选择
  if [ $is_self_domain -eq 1 ]; then
    if ! applyLE $domain $webIp; then
      echo "申请证书失败!"
      return 1
    fi
  else  # 没有自定义域名时，webip是内置固定的，就是web(x).serv00.com
    if ! applyLE $domain ; then
      echo "申请证书失败!"
      return 1
    fi
  fi
  green "安装完毕!"
  
}

makeWWW(){
  local proc=$1
  local port=$2
  local www_type=${3:-"proxy"}
  
  echo "正在处理服务IP,请等待..."
  is_self_domain=0
  webIp=$(get_webip)
  default_webip=$(get_default_webip)
  green "可用webip是: $webIp, 默认webip是: $default_webip"
  read -p "是否使用自定义域名? [y/n] [n]:" input
  input=${input:-n}
  if [[ "$input" == "y" ]]; then
    is_self_domain=1
    read -p "请输入域名(确保此前域名已指向webip):" domain
  else
    user="$(whoami)"
    if isServ00 ; then
      domain="${proc}.$user.serv00.net"
    else
      domain="$proc.$user.ct8.pl"
    fi
  fi

  if [[ -z "$domain" ]]; then
    red "输入无效域名!"
    return 1
  fi
  
  domain=${domain,,}
  echo "正在绑定域名,请等待..."
  if [[ "$www_type" == "proxy" ]]; then
    resp=$(devil www add $domain proxy localhost $port)
  else
    resp=$(devil www add $domain php)
  fi
  #echo "resp:$resp"
  if [[ ! "$resp" =~ .*succesfully.*$  && ! "$resp" =~ .*Ok.*$ ]]; then 
     if [[ ! "$resp" =~ "This domain already exists" ]]; then 
        red "申请域名$domain 失败！"
        return 1
     fi
  fi
  
  # 自定义域名的特殊处理
  if [[ $is_self_domain -eq 1 ]]; then
    host="$(hostname | cut -d '.' -f 1)"
    sno=${host/s/web}
    default_webIp=$(devil vhost list public | grep "$sno" | awk '{print $1}')
    rid=$(devil dns list "$domain" | grep "$default_webIp" | awk '{print $1}')
    resp=$(echo "y" | devil dns del "$domain" $rid)
    #echo "resp:$resp"
  else 
    webIp=$(get_default_webip)
  fi
  # 保存信息
  if [[ "$www_type" == "proxy" ]]; then
  cat > config.json <<EOF
  {
     "webip": "$webIp",
     "domain": "$domain",
     "port": "$port"
  }
EOF
  fi

  green "域名绑定成功,你的域名是:$domain"
  green "你的webip是:$webIp"
}

startSunPanel(){
  local workdir="${installpath}/serv00-play/sunpanel"
  local exepath="${installpath}/serv00-play/sunpanel/sun-panel"
  if [[ ! -e $exepath ]]; then
     red "未安装，请先安装!"
     return 
  fi
  cd $workdir
  if checkProcAlive "sun-panel"; then
     stopProc "sun-panel"
  fi
  read -p "是否需要日志($workdir/running.log)? [y/n] [n]:" input
  input=${input:-n}
  local args=""
  if [[ "$input" == "y" ]]; then
    args=" > running.log 2>&1 "
  else
    args=" > /dev/null 2>&1 "
  fi
  cmd="nohup ./sun-panel $args &"
  eval "$cmd"
  sleep 1
  if checkProcAlive "sun-panel"; then
     green "启动成功"
  else 
     red "启动失败"
  fi

}


burnAfterReadingServ(){
   if ! checkInstalled "serv00-play"; then
      return 1
    fi
    while true; do
    yellow "---------------------"
    echo "1. 安装"
    echo "2. 卸载"
    echo "9. 返回主菜单"
    echo "0. 退出脚本"
    yellow "---------------------"
    read -p "请选择:" input

    case $input in
    1) installBurnReading
       ;;
    2) uninstallBurnReading
       ;;
    9) break
      ;;
    0) exit 0
       ;;
    *)  echo "无效选项，请重试"
      ;;
    esac 
  done
  showMenu
}

installBurnReading(){
   local workdir="${installpath}/serv00-play/burnreading"

   if [[ ! -e "$workdir" ]]; then
      mkdir -p $workdir
   fi
  cd $workdir 

  if  ! check_domains_empty; then
    red "已有安装如下服务，是否继续安装?"
    print_domains
    read -p "继续安装? [y/n] [n]:" input
    input=${input:-n}
    if [[ "$input" == "n" ]]; then
       return 0
    fi
  fi
  
  domain=""
  webIp=""
  if ! makeWWW burnreading "null" php ; then
    echo "绑定域名失败!"
    return 1
  fi
  
  domainPath="$installpath/domains/$domain/public_html"
  cd $domainPath
  echo "正在下载并安装 OneTimeMessagePHP ..."
  if ! download_from_github_release frankiejun OneTimeMessagePHP OneTimeMessagePHP; then
      red "下载失败!"
      return 1
  fi
  passwd=$(uuidgen -r )
  sed -i '' -e "s/^ENCRYPTION_KEY=.*/ENCRYPTION_KEY=\"$passwd\"/" \
              -e "s|^SITE_DOMAIN=.*|SITE_DOMAIN=\"$domain\"|" "env"
  mv env .env
  echo "已更新配置文件!"

  read -p "是否申请证书? [y/n] [n]:" input
  input=${input:-'n'}
  if [[ "$input" == "y" ]]; then
    echo "正在申请证书，请等待..."
    if ! applyLE $domain $webIp; then
      echo "申请证书失败!"
      return 1
    fi
  fi
  cd $workdir 
  add_domain $domain $webIp

  echo "安装完成!"
}

uninstallBurnReading(){
  local workdir="${installpath}/serv00-play/burnreading"

  if [[ ! -e "$workdir" ]]; then
     echo "已没有可以卸载的服务!"
     return 1
  fi 

  cd $workdir

  if ! check_domains_empty; then
     echo "目前已安装服务的域名有:"
     print_domains
  fi
  read -p "是否删除所有域名服务? [y/n] [n]:" input
  input=${input:-n}
  if [[ "$input" == "y" ]]; then
    delete_all_domains
    rm -rf "${installpath}/serv00-play/burnreading"
  else
    read -p "请输入要删除的服务的域名:" domain
    delete_domain "$domain"
  fi

}

websshServ(){
    if ! checkInstalled "serv00-play"; then
      return 1
    fi
    while true; do
    yellow "---------------------"
    echo "webssh:"
    echo "服务状态: $(checkProcStatus wssh)"
    echo "1. 安装/修改配置"
    echo "2. 启动"
    echo "3. 停止"
    echo "8. 卸载"
    echo "9. 返回主菜单"
    echo "0. 退出脚本"
    yellow "---------------------"
    read -p "请选择:" input

    case $input in 
    1) installWebSSH
      ;;
    2) startWebSSH
      ;;
    3) stopWebSSH
      ;;
    8) uninstallWebSSH
      ;;
    9) break
      ;;
    0) exit 0
       ;;
    *)  echo "无效选项，请重试"
      ;;
    esac 
 done
   showMenu
}

uninstallWebSSH(){
  local workdir="${installpath}/serv00-play/webssh"
  uninstallProc "$workdir" "wssh"
}

installWebSSH(){
  local workdir="${installpath}/serv00-play/webssh"
  if [[ ! -e "$workdir" ]]; then
     mkdir -p $workdir
  fi
  cd $workdir
  configfile="./config.json"
  local is_installed=0
  if [ -e "$configfile" ]; then
    is_installed=1
    echo "已安装，配置如下:"
    cat $configfile

    read -p "是否修改配置? [y/n] [n]:" input
    input=${input:-n}
    if [[ "$input" == "n" ]]; then
      return 
    fi
  fi
  
  port=""
  loadPort
  randomPort tcp "webssh"
  if [ -n "$port" ]; then
    websshPort=$port
  else
    echo "未输入端口!"
    return 1
  fi

#   cat > $configfile <<EOF
#   {
#     "port": $websshPort
#   }
# EOF

  if [[ $is_installed -eq 0 ]]; then
    echo "正在安装webssh..."
    pip install webssh
  fi
  
  user="$(whoami)"
  target_path="/home/$user/.local/bin"
  wsshpath="$target_path/wssh"
  if [[ ! -e "$wsshpath" ]]; then
    red "安装webssh失败 !"
    return 1
  fi
  cp $wsshpath $workdir
  profile="${installpath}/.profile"
  
  if ! grep -q "export PATH=.*$target_path" "$profile"; then
     echo "export PATH=$target_path:\$PATH" >> "$profile"
     source $profile
  fi
  domain=""
  webIp=""
  if ! makeWWW ssh $websshPort ; then
    echo "绑定域名失败!"
    return 1
  fi
  if ! applyLE $domain $webIp; then
    echo "申请证书失败!"
    return 1
  fi
  echo "安装完成!"
  
}

stopWebSSH(){
  stopProc "wssh"
  sleep 2
  if ! checkProcAlive "wssh"; then
     echo "wssh已停止！"
  else
     echo "未能停止，请手动杀进程!"
  fi
}

startWebSSH(){
  local workdir="${installpath}/serv00-play/webssh"
  local configfile="$workdir/config.json"
  if [ ! -e "$configfile" ]; then
     echo "未安装，请先安装!"
     return 
  fi
  cd $workdir
  read -p "是否需要日志($workdir/running.log)? [y/n] [n]:" input
  input=${input:-n}
  args=""
  if [[ "$input" == "y" ]]; then
     args=" > running.log 2>&1 "
  else
     args=" > /dev/null 2>&1 "
  fi
  port=$(jq -r ".port" $configfile)
  if checkProcAlive "wssh"; then
    stopProc "wssh"
  fi
  echo "正在启动中..."
  cmd="nohup ./wssh --port=$port --fbidhttp=False --xheaders=False --encoding='utf-8' --delay=10  $args &"
  eval "$cmd"
  sleep 2
  if checkProcAlive wssh; then
    green "启动成功！"
  else
    echo "启动失败!"
  fi
}


checkInstalled(){
  local model=$1
  if [[ "$model" == "serv00-play" ]]; then
     if [[ ! -d "${installpath}/$model" ]]; then 
        red "请先安装$model !!!"
        return 1
     else 
        return 0
     fi
  else
     if [[ ! -d "${installpath}/serv00-play/$model" ]]; then 
        red "请先安装$model !!!"
        return 1
     else 
        return 0
     fi
  fi
  return 1
}


showMenu(){
  art_wrod=$(figlet "serv00-play")
  echo "<------------------------------------------------------------------>"
  echo -e "${CYAN}${art_wrod}${RESET}"
  echo -e "${GREEN} 烟神殿大模型AI中转服务:https://yansd666.top${RESET}"
  echo "<------------------------------------------------------------------>"
  echo "请选择一个选项:"

  options=("安装/更新serv00-play项目" "sun-panel"  "webssh"  "阅后即焚"  "设置保活的项目" \
           "快照恢复" "系统初始化" "前置工作及设置中国时区" "设置彩色开机字样" "显示本机IP" \
          "alist管理" "端口管理" "域名证书管理" "自动检测主机IP状态" "卸载" )

  select opt in "${options[@]}"
  do
      case $REPLY in
          1)
              install
              ;;
          2)
              sunPanelServ
              ;;
          3)
              websshServ
              ;;
          4)
              burnAfterReadingServ
              ;;
          5)
            setConfig
            ;;
        6)
            ImageRecovery
            ;;
        7)
            InitServer
            ;;
        8)
           setCnTimeZone
           ;;
        9)
           setColorWord
           ;;
        10)
           showIP
           ;;
        11)
           alistServ
           ;;
        12)
           portServ
           ;;
        13)
           domainSSLServ
           ;;
        14)
           getUnblockIP
           ;;
        15)
            uninstall
            ;;
        0)
              echo "退出"
              exit 0
              ;;
          *)
              echo "无效的选项 "
              ;;
      esac
      
  done

}


showMenu