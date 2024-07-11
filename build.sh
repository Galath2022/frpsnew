#!/bin/sh

# build script for armsoft project

MODULE="frpsnew"
VERSION="0.59"
TITLE="frps穿透服务器"
DESCRIPTION="内网穿透利器，谁用谁知道。"
HOME_URL="Module_frpsnew.asp"
TAGS="网络 穿透"
AUTHOR="Galahad"

# Check and include base
DIR="$( cd "$( dirname "$BASH_SOURCE[0]" )" && pwd )"

do_build_result() {
	rm -f ${MODULE}/.DS_Store
	rm -f ${MODULE}/*/.DS_Store
	rm -f ${MODULE}.tar.gz

	if [ -z "$TAGS" ];then
		TAGS="其它"
	fi
	
	# add version to the package
	cat > ${MODULE}/version <<-EOF
	${VERSION}
	EOF
	
	tar -zcvf ${MODULE}.tar.gz $MODULE
	md5value=$(md5sum ${MODULE}.tar.gz | tr " " "\n" | sed -n 1p)
	cat > ./version <<-EOF
	${VERSION}
	${md5value}
	EOF
	cat version
	
	DATE=$(date +%Y-%m-%d_%H:%M:%S)
	cat > ./config.json.js <<-EOF
	{
	"version":"$VERSION",
	"md5":"$md5value",
	"home_url":"$HOME_URL",
	"title":"$TITLE",
	"description":"$DESCRIPTION",
	"tags":"$TAGS",
	"author":"$AUTHOR",
	"link":"$LINK",
	"changelog":"$CHANGELOG",
	"build_date":"$DATE"
	}
	EOF
	
}

# change to module directory
cd $DIR

# do something here
do_build_result