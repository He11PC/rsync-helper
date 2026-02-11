# \[rsync\] Helper script

I've created this script to make my regular rsync backups easier.

---

## Files:

The script requires 3 files to function.

- **backup.sh:** the actual script

- **config.cfg:** the configuration file

- **ignorelist:** directories you don't want to backup, inspired by **rubo77** list. Visit [rsync-homedir-excludes](https://github.com/rubo77/rsync-homedir-excludes) for more information

---

## Usage:

- Download the script corresponding to your language

- Download the configuration file and edit it to suit your needs
   
- Modify the **ignorelist** as needed

- Make the script executable:

> `chmod u+x /path/to/your/script.sh`

- Launch the script manually:

> `cd /path/to/your/script`  
> `./script.sh`

You can also create a shortcut with an icon on your desktop environment (don't forget to execute in a terminal).

&nbsp;
&nbsp;

:warning: **The rsync commands are commented out inside the script to prevent a missconfiguration disaster**

> Run the script, try a simulation and a backup, then verify if the rsync commands are correct.  
> If they are, edit the script and uncomment the rsync commands on lines 349 and 361 by removing the # character to enable them.
