ddgrey is a dynamic and optionally distributed greylisting daemon.

It acts as a normal greylisting daemon, being queried over a UNIX domain socket
from a MTA, and answering if a mail should be allowed, defered or denied.

It can also get reports from the MTA (currently by reading exim4 log files)
about suspect activities, and receive reports from spamtraps, spam reporting
aliases and ddgrey servers on other hosts (normally on your other MX servers).

Using this information, ddgrey can adjust the greylisting delay for a specific
host from no greylist at all, to a long delay or outright blacklisting.

Using ddgrey together with the supplied exim4 ACL snippet will also mean
some attempts are made to prevent information leakage to spammers, in
particular about which recipients are valid, and about spamtraps.

IP and domain reputation
------------------------
An extension to normal greylisting is that the verified reverse domain
of the sending IP (if any) is used in addition to only the IP itself.
This automatically allevitates problems when mail are retried from different
hosts in a pool, and also increases reputation faster for the whole domain.

The main difference between ddgrey and spam filters like SpamAsssasin is
that ddgrey is an IP address (and domain) reputation checking tool, while
SpamAssisin will check message reputation (where address is only a small part).

Credits and copyright
=====================
© 2020 Per Eric Rosén (per@rosnix.net). Distributed under GNU GPL 3.0.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version. See the file "LICENSE".

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

exim4.conf based on configuration for greylistd by Tor Slettnes.

This distribution includes a fixed version of Perl6::Parameters.
Copyright © 2001 Brent Dax. Distributed under the same terms as perl.

System requirements
===================
unix system (preferrably with exim4 MTA)
perl5 >= 5.14

package              debian package
-----------------------------------
Net::DNS >= 0.81     libnet-dns-perl
Net::Netmask         libnet-netmask-perl
Date::Manip          libdate-manip-perl
List::MoreUtils      liblist-moreutils-perl
DBD::SQLite          libdbd-sqlite3-perl
Domain::PublicSuffix libdomain-publicsuffix-perl
Cache::MemoryCache   libcache-cache-perl
Email::Received	     libemail-received-perl
Email::MIME	     libemail-mime-perl
Date::Parse	     libtimedate-perl

Installation
============
ddgreyd normally run as user "daemon". If you use Exim 4 under Debian,
change RUNUSER and RUNGROUP in Makefile to "Debian-exim".

"make install" will install in /usr/local and /var (if root) or in $HOME.
It will also install a default configuration file in /etc/ddgrey (if root)
or $HOME/.ddgrey if no such file exists.

exim4 configuration
-------------------
if you use Exim 4, add the line "service exim4" to /etc/ddgrey/ddgrey.conf.
This will make ddgrey parse /var/log/exim4/mainlog for IP address reputation.

Add the lines in file exim4.conf to your exim4 rcpt ACL configuration; this
is located in /etc/exim4/conf.d/acl/30_exim4-config_check_rcpt if you
use the Debian split exim configuration.

peering with other ddgrey servers
--------------------------------
If you have other ddgrey servers you wish to communicate with,
add lines "peer = <hostname>" to /etc/ddgrey/ddgrey.conf for each server.
Please ensure in your firewall that they can reach each other on TCP port 722.

ddgrey has no built-in authentication mechanism. Ensure that you only
add trusted hosts, for example from an internal VPN.

using spamtraps
---------------
If you wish to set up spamtraps, add the trap addresses to your aliases files
piped to /dev/null, like "trap.trapson: /dev/null".

Add the fully qualified trap addresses to /etc/ddgrey/spamtraps. The format is
similiar to an aliases file with lines like:
<fully qualified address>:"hard"|"soft".

"soft" and "hard" determine how hard you wish to punish servers for using the
trap. "hard" means instant blacklisting - if no redeeming qualities of the
server are found. Normal practice is to use "hard" for made-up addresses never
used for legitimate email, and "soft" for old now unused email addresses.

Ensure there is a line "traps = <your spamtraps file>" in /etc/ddgrey.conf.
If you use the default config there is already such a line.

Add that email adresses to you web pages, and make it only visible to spam 
harvesting robots, for example by putting it in a hidden div.

spam reporting alias
--------------------
If you wish to manually report spam, you can set up a spam reporting alias
at some of your domains. Add a line <spam>:"|/<path>/ddgrey-report" to your
alises file where <spam> is a local part of your choice, and <path> is
the path where ddgrey binaries are installed.

You should also ensure that all hosts you trust to report spam
are listed with a line "trusted = <ip or network>" in ddgrey.conf.

If you wish to send feedback on unparseable spam reports, please add
"return_output = true" to the pipe transport for your alises file. 


Configuration directives
========================
Configuration is done in /etc/ddgrey/ddgrey.conf

The only variables you usually need changing are:

peer	hostname of cooperating ddgrey servers (usually on your other MX)
service	"exim4" to follow exim4 log files

Other possible variables (default in parentesis):

general
-------
user		run as this user (daemon)

greylisting
-----------
trusted		name/ip/range to always allow mail from

search_duration	how long time back to look for good and bad behaviour (60 days)
retry		how long time back to look for retries (same as search_duration)
policy_duration	how long a saved policy will be kept from last update (7 days)

grey_default	default delay for unknown hosts (4 hours)
grey_short	delay for somewhat trusted hosts (10 minutes)
grey_min	delay for even more trusted hosts (10 seconds)
grey_max	maximum delay before blacklisting (24 hours)
blacklist	duration of blacklisting (60 days)

RBL lookups
-----------
rbls		RBL services to use (spamcop sorbs uce-2)
		possible values:
		barracuda (requires first asking for permission)
		sorbs
		spamcop
		spamhaus (only free for non-commercial use)
		uce-2
		uce-3

rbl_score <name> <score>
	  	 Score (usually negative) for a match in RBL <name>

MTA interaction
---------------
service 	"exim4": follow exim mainlog
exim4_mainlog	location of exim4 mainlog (/var/log/exim4/mainlog)

exim4_unknown	"delivery": notice attempts to deliver to unknown recipient
                using exim4 log entries made during standard delivery attempt

		"verify": use exim4 log entry made by special validation done
		before greylisting. This is included in ddgrey exim4.conf
		and will log all attempts to send to unknown recipients,
		including attempts caught by grey- and blacklisting. (default) 

spamtraps
---------
traps		aliases-formatted file with spamtraps. automatically reloaded
hard_trap	hard spamtrap email address
soft_trap	soft spamtrap email address

manual reports
--------------
report_verify	only allow manual reports for mail already seen as accepted

network replication
-------------------
name		use this name as hostname (default: hostname -f)
port 		use port fort TCP server

accept_reader <name>
		accept sending reports to <name>
		(can also be ip address or range)

accept_writer <name>
		accept receiving reports from <name>
      		(can also be ip address or range)

accept <name>
		accept sending to and receiving reports from <name>
 		(can also be ip address or range)

server_read <namn> [<port>]
            	download reports from <name> (can also be ip address)
		use <port> instead of default if specified

peer <namn> [<port>]
		same as server_read and accept_reader for <name>
		use <port> instead of default if specified

Spamtraps file
==============
The format of the spamtraps file is line like:
<qualified email>:(hard|soft)

Debug levels
============
0	log normal messages including long-term client connect and disconnect
1	also log short-term client connect and disconnect, policy changes
2	also log processing of each report, DNS queries
3	also log each protocol line sent and received

Protocol for greylist (SMTP-like)
=================================

check <ip> <from> <to>
    answer "200 white", "200 grey" o "200 black" 

check_and_quit <ip> <from> <to>
    answer "white", "grey" or "black" without newline, then close the connection

quit
    close the connection

Protocol for peering (SMTP-like)
================================

list [<t>]
    list reports on server (possibly from timestamp <t>)

get <n>
    get report with remote id <n>

subscribe [<t>]
    continously send reports
    if <t> is given, also send stored reports from timestamp <t>

quit
    quit the connection
