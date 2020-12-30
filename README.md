# nagisk2

A nagios plugin for checking asterisk using AMI

# Setup

Add a AMI user in `/etc/asterisk/manager.conf`:

```text
[nagios]
secret = your_secret_password
deny=0.0.0.0/0.0.0.0
# allow only from localhost
permit=127.0.0.1/255.255.255.0
# we just need the read reporting permission
read = reporting
writetimeout = 5000
```

Adjust parameters in [nagisk2.pl](nagisk2.pl):

```perl5
use constant R_PORT => 5038;
use constant IP_ADDR => 'localhost';
use constant AMI_USER => 'nagios';
use constant AMI_PASS => 'your_secret_password';
```

And finally, copy this file to `$nagios_plugindir` (usually `/usr/lib/nagios/plugins`) and set up a command.

# Supported commands

- `pjsip_outbound_registry`: Checks a outbound trunk.

# Contributing

Besides, being useful as is (hopefully) - this script should also serve as skeleton for other checks. If you follow this
simple recipe you should be able to easily implement your own checks:

- Insert a check method according to the template in the header of [nagisk2.pl](nagisk2.pl).
- Add your command to initial the `for()`-block (there is a commented-out example).
- Add your command to the `show_help()` function.
- Create a pull request with your extension :)