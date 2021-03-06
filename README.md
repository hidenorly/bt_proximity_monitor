# bt_proximity_monitor

Watch whether bt devices (your phone, etc) is in ranged or not and do something.

# Dependency

* hcitool / rfcomm (default)
* l2ping (if specified -d l2ping)
  * Please pair by rfcomm connection with your iPhone in advance. After that, your iPhone will ack by the l2ping.
* ruby (confirmed on 2.2 but other versions should be fine too)
* Confirmed OS is Ubuntu Mate 16.04 LTS on Raspberry Pi3 but others should be fine too.

# You can set target device

```
./bt_proximity_monitor.rb -t 70:EC:E4:XX:XX:XX
```

or

```devices.cfg
70:EC:E4:XX:XX:XX iPhone1
70:EC:E4:XX:XX:XY iPhone2
```


# You can set time schedule rules flexibly

You can specify when is needed to take action by specific date, week and time duration.
You can specify execution commands at initialization(onStart)/termination(onEnd)/device proximiy(onConnected/onDisconnected).

```rules.cfg
[13:30-23:30 Mon Tue Wed Thu Fri Sat Sun]
#onStart
echo "blub On"
bleBulbDriver.rb allOn
#onEnd
bleBulbDriver.rb allOff
#onConnected
bleBulbDriver.rb allOff
#onConnected if iPhone1
echo "Found iPhone1"
#onDisconnected if 3 times
bleBulbDriver.rb allOn

[2017-01-01 03:00-03:26 (random:1hour)]
#onStart
bleBulbDriver.rb allOn
#onEnd
bleBulbDriver.rb allOff
#onConnected
bleBulbDriver.rb allOff
#onDisconnected
bleBulbDriver.rb allOn
```

You can specify randomization as ```(random:30min)```, ```(random:1hour)```, etc in the condition field.

```
[16:30-23:30 Mon Tue Wed Thu Fri Sat Sun (random:30min)]
[2017-01-01 03:00-03:26 (random:1hour)]
```

# To execute this as service (on Ubuntu)

```
$ sudo ./install.sh
```

* The ruby file is stored under /opt
* The configuration files are stored under /var/opt/btproximity

# Recommended detection

1. Establish BT connection with rfcomm first.
```
./bt_proximity_monitor.rb -t 70:EC:E4:XX:XX:XX
```
And please accept the pairing from the running device to your iPhone, etc. on your iPhone.

2. Use BT Proximity detection with l2ping

```
./bt_proximity_monitor.rb -t 70:EC:E4:XX:XX:XX -d l2ping
```

Please note that iPhone is very secure device and then before accepting the pairing from the running device, iPhone will not respond for the l2ping query.
