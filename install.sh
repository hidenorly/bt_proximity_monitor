#!/bin/bash

echo installing bt_proximity_monitor service
echo Please note that sudo execution is required.

cp bt_proximity_monitor.rb /opt
cp btproximity.service /etc/systemd/system

mkdir /var/opt/btproximity
cp rules.cfg /var/opt/btproximity

systemctl enable btproximity

echo "To configure the rules, do vim /var/opt/btproximity/rules.cfg"
echo "To add your phone's mac address, do vim /var/opt/btproximity/devices.cfg"
echo "To start the service, do sudo systemctl start btproximity"
echo "When configuration is changed, do sudo systemctl restart btproximity"
echo ""
echo "To uninstall the service, do sudo systemctl disable btproximity"
echo "Then you can do rm /opt/bt_proximity_monitor.rb, rm -rf /var/opt/btproximity"
