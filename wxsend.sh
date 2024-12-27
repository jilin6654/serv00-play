#!/bin/bash

text=$1

webhook=${WECOM_WEBHOOK}
URL="${webhook}"

if [[ -z ${webhook} ]]; then
  echo "未配置企业微信机器人webhook地址，请在企业微信群中添加机器人并获取webhook地址"
else
  # 构建请求体
  json_data="{\"msgtype\": \"text\", \"text\": {\"content\": \"${text}\"}}"
  
  res=$(timeout 20s curl -s -X POST -H "Content-Type: application/json" $URL -d "$json_data")
  if [ $? == 124 ]; then
    echo "发送消息超时"
    exit 1
  fi

  errcode=$(echo "$res" | jq -r ".errcode")
  if [ "$errcode" == "0" ]; then
    echo "企业微信推送成功"
  else
    errmsg=$(echo "$res" | jq -r ".errmsg")
    echo "企业微信推送失败, errcode:$errcode, errmsg:$errmsg"
  fi
fi
