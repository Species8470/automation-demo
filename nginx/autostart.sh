sudo touch /etc/rc.local
sudo chmod 777 /etc/rc.local
sudo echo "/etc/init.d/realserver.sh" > /etc/rc.local
sudo echo "exit 0" >> /etc/rc.local
