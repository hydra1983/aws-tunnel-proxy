#!/bin/bash

# ----------------------------------------
# ONLY WORKING WITH UBUNTU
# ----------------------------------------
AWS_HOST=
AWS_PORT=
AWS_USER=ubuntu
AWS_KEY_NAME=
AWS_KEY_PATH=~/.ssh
PROXY_HOST=
PROXY_PORT=
PROXY_USER=
PROXY_PASS=
PROXY_KEY_NAME=
PROXY_KEY_PATH=
SSHTUNNEL_KEY_NAME=id_rsa.sshtunnel

function build_scripts {
AWS_SCRIPTS=$(cat <<EOF
	echo Line should be omitted 1>/dev/null

	sudo su
	useradd -N sshtunnel
	mkdir -p /home/sshtunnel/.ssh
	ssh-keygen -q -t rsa -N "" -f /home/sshtunnel/.ssh/$SSHTUNNEL_KEY_NAME
	cat /home/sshtunnel/.ssh/id_rsa.sshtunnel.pub > /home/sshtunnel/.ssh/authorized_keys
	chown sshtunnel /home/sshtunnel/.ssh/authorized_keys
	chmod 600 /home/sshtunnel/.ssh/authorized_keys
	cp /home/sshtunnel/.ssh/$SSHTUNNEL_KEY_NAME /home/ubuntu/
	chown ubuntu /home/ubuntu/$SSHTUNNEL_KEY_NAME
EOF)

LOCAL_SCRIPTS=$(cat <<EOF
	echo Line should be omitted 1>/dev/null

	scp -P $AWS_PORT -i $AWS_KEY_PATH/$AWS_KEY_NAME $AWS_USER@$AWS_HOST:$SSHTUNNEL_KEY_NAME /var/tmp/$SSHTUNNEL_KEY_NAME

	if [ "$PROXY_KEY_NAME" != "" ] ; then
		scp -P $PROXY_PORT -i $PROXY_KEY_PATH/$PROXY_KEY_NAME /var/tmp/$SSHTUNNEL_KEY_NAME $PROXY_USER@$PROXY_HOST:
	else
		sshpass -p "$PROXY_PASS" scp -P $PROXY_PORT /var/tmp/$SSHTUNNEL_KEY_NAME $PROXY_USER@$PROXY_HOST:
	fi

	rm /var/tmp/$SSHTUNNEL_KEY_NAME
EOF)

PROXY_SCRIPTS=$(cat <<EOF
	echo Line should be omitted 1>/dev/null

	sudo mkdir -p /opt/sshtunnel/
	sudo chown root ~/$SSHTUNNEL_KEY_NAME
	sudo chmod 600 ~/$SSHTUNNEL_KEY_NAME
	sudo scp -i ~/$SSHTUNNEL_KEY_NAME $AWS_USER@$AWS_HOST:$SSHTUNNEL_KEY_NAME /opt/sshtunnel/
	sudo rm ~/$SSHTUNNEL_KEY_NAME

	sudo su
	apt-get update
	apt-get install -y --force-yes privoxy autossh
	echo "$(cat /etc/privoxy/config | sed -r 's/^(listen\-address.*localhost\:8118)$/#\1/')" > /etc/privoxy/config
	echo "listen-address 0.0.0.0:8118" >> /etc/privoxy/config
	echo "forward-socks5 localhost:1080" >> /etc/privoxy/config

	wget https://gist.github.com/hydra1983/4077225/raw/d59160dcbd6c490b997b225c36fd1315b4b76e46/sshtunnel -O /etc/init.d/sshtunnel
	chmod +x /etc/init.d/sshtunnel
	echo "$(cat /etc/init.d/sshtunnel | sed "s/^RSERVER=.*$/RSERVER=$AWS_HOST/")" > /etc/init.d/sshtunnel
	echo "$(cat /etc/init.d/sshtunnel | sed "s/^RPORT=.*$/RPORT=$AWS_PORT/")" > /etc/init.d/sshtunnel
	echo "$(cat /etc/init.d/sshtunnel | sed "s/^IDENTITY_FILE=.*$/IDENTITY_FILE=\/opt\/sshtunnel\/$SSHTUNNEL_KEY_NAME/")" > /etc/init.d/sshtunnel

	[ -d ~/.ssh ] || mkdir ~/.ssh
	[ -f ~/.ssh/config ] || touch ~/.ssh/config
	[ "$(grep 'Host \*' ~/.ssh/config)" == "" ] && (echo 'Host *' >> ~/.ssh/config && echo "StrictHostKeyChecking no" >> ~/.ssh/config)

	/etc/init.d/sshtunnel start
	/etc/init.d/privoxy restart
	update-rc.d sshtunnel defaults
EOF)
}

function build_test_scripts {
AWS_SCRIPTS=$(cat <<EOF
	echo Line should be omitted 1>/dev/null
	echo scripts run on aws server
EOF)

LOCAL_SCRIPTS=$(cat <<EOF
	echo Line should be omitted 1>/dev/null
	echo scripts run on local machine
EOF)

PROXY_SCRIPTS=$(cat <<EOF
	echo Line should be omitted 1>/dev/null
	echo scripts run on proxy server
EOF)
}

function install {
if [ "$1" == "install" ] ; then
	build_scripts
else
	build_test_scripts
fi

if [ -s $AWS_KEY_PATH/$AWS_KEY_NAME ] && ( [ -s $PROXY_KEY_PATH/$PROXY_KEY_NAME ] || [ "$PROXY_PASS" != "" ] ) ; then
	ssh -p $AWS_PORT -i $AWS_KEY_PATH/$AWS_KEY_NAME $AWS_USER@$AWS_HOST sh -c "$AWS_SCRIPTS"
	sh -c "$LOCAL_SCRIPTS"

	if [ "$PROXY_KEY_NAME" != "" ] ; then
		ssh -p $PROXY_PORT -i $PROXY_KEY_PATH/$PROXY_KEY_NAME $PROXY_USER@$PROXY_HOST sh -c "$PROXY_SCRIPTS"
	else
		sshpass -p "$PROXY_PASS" ssh -p $PROXY_PORT $PROXY_USER@$PROXY_HOST sh -c "$PROXY_SCRIPTS"
	fi
fi
}

[ -s ./aws_proxy_auto.conf ] && source ./aws_proxy_auto.conf && install $*
