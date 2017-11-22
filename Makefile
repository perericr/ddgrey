# ---- settings ----

export PROGRAM = ddgrey
export VERSION = $(shell head -1 changelog |tr '()' '|'|cut -d '|' -f2)
export PV      = $(PROGRAM)-$(VERSION)

ifeq ($(shell id -u),0)
    export RUNUSER ?= daemon
    export RUNGROUP ?= daemon
    # export RUNUSER  ?= Debian-exim
    # export RUNGROUP ?= Debian-exim
else
    export RUNUSER  ?= $(USER)
    export RUNGROUP ?= $(USER)
endif

ifeq ($(shell id -u),0)
    export BASE?=/usr/local
else
    export BASE?=$(HOME)
endif

export BINDIR     ?= $(BASE)/bin
export LOCALEDIR  ?= $(BASE)/share
ifeq ($(shell id -u),0)
    export SBINDIR     ?= $(BASE)/sbin
else
    export SBINDIR     ?= $(BASE)/bin
endif

ifeq ($(shell id -u),0)
    export PERLLIBDIR ?= $(BASE)/lib/site_perl
else
    export PERLLIBDIR ?= $(BASE)/lib/perl5
endif
ifeq ($(shell id -u),0)
    export CONFIGDIR?=/etc/ddgrey
else
    export CONFIGDIR?=$(HOME)/.ddgrey
endif
ifeq ($(shell id -u),0)
    export DATADIR?=/var/lib/ddgrey
else
    export DATADIR?=$(HOME)/.ddgrey
endif
ifeq ($(shell id -u),0)
    export RUNDIR?=/var/run/ddgrey
else
    export RUNDIR?=$(HOME)/.ddgrey
endif

# INSTALL_prefix is used for making packages
ifdef DESTDIR
    export INSTALL_PREFIX=$(DESTDIR)
endif

# ---- files ----

BIN     = $(addprefix build-tmp/,ddgrey ddgrey-report)
SBIN    = $(addprefix build-tmp/,ddgreyd)
PERLLIB	= $(addprefix build-tmp/,Client.pm ClientConnection.pm Config.pm DBModel.pm DBStore.pm Dispatcher.pm DNS.pm Exim4.pm GreylistClientConnection.pm GreylistServer.pm LocalServer.pm MainConfig.pm Parameters.pm Policy.pm ReadClient.pm RemoteServer.pm Report.pm ReportClient.pm Reporter.pm Run.pm Select.pm Server.pm SQLite.pm Sync.pm SyncClientConnection.pm TailReporter.pm Traps.pm)
CONFIG  = $(addprefix build-tmp/,ddgrey.conf)
DATA	= public_suffix_list.dat
OBJ	= $(BIN) $(SBIN) $(PERLLIB) $(CONFIG)
TMP     = build-tmp debian/ddgrey
# SUB	= locale/sv_SE/LC_MESSAGES

# ---- dependencies ----

.PHONY : default build install clean
default : build

build-tmp/% : % build-tmp Makefile
	perl -pwe "s|_RUNUSER_|$(RUNUSER)|g;s|_VERSION_|$(PV)|g;s|_CONFIGDIR_|$(CONFIGDIR)|g;s|_BINDIR_|$(BINDIR)|g;s|_SBINDIR_|$(SBINDIR)|g;s|_DATADIR_|$(DATADIR)|g;s|_RUNDIR_|$(RUNDIR)|g;s|_LOCALEDIR_|$(LOCALEDIR)|g;s|_PERL5LIB_|$(PERLLIBDIR)|g;s|.*USELIB.*|use lib '$(PERLLIBDIR)';|;" < $< > $@

$(PROGRAM).po : $(BIN) $(SBIN)
	xgettext --foreign-user -d $(PROGRAM) $(BIN) $(SBIN)

public_suffix_list.dat:
	wget -N https://publicsuffix.org/list/public_suffix_list.dat

$(TMP) :
	mkdir -p $@

# ---- commands ----

build : $(OBJ)
    ifdef SUB
	for I in $(SUB);do ($(MAKE) -C $$I build);done
    endif

clean :
    ifdef OBJ
	rm -f $(OBJ)
    endif
	rm -rf $(TMP)
    ifdef SUB
	for I in $(SUB);do ($(MAKE) -C $$I clean);done
    endif

install : build
    ifdef BIN
	install -d $(INSTALL_PREFIX)$(BINDIR)
	install -m 755 $(BIN) $(INSTALL_PREFIX)$(BINDIR)
    endif
    ifdef SBIN
	install -d $(INSTALL_PREFIX)$(SBINDIR)
	install -m 755 $(SBIN) $(INSTALL_PREFIX)$(SBINDIR)
    endif
    ifdef CONFIG
	install -d $(INSTALL_PREFIX)$(CONFIGDIR)
	for C in $(notdir $(CONFIG));do test -f $(INSTALL_PREFIX)$(CONFIGDIR)/$$C || install -m 640 build-tmp/$$C $(INSTALL_PREFIX)$(CONFIGDIR);done
    endif
    ifdef MAN1
	install -d $(INSTALL_PREFIX)$(MANDIR)/man1
	install -m 644 $(MAN1) $(INSTALL_PREFIX)$(MANDIR)/man1
    endif
    ifdef PERLLIB
	scripts/pm-install -m 644 $(PERLLIB) $(INSTALL_PREFIX)$(PERLLIBDIR)
    endif
    ifdef DATADIR
	install -o $(RUNUSER) -g $(RUNGROUP) -d $(INSTALL_PREFIX)$(DATADIR)
	install -o $(RUNUSER) -g $(RUNGROUP) -m 644 $(DATA) $(INSTALL_PREFIX)$(DATADIR)
    endif
    ifdef RUNDIR
	install -o $(RUNUSER) -g $(RUNGROUP) -d $(INSTALL_PREFIX)$(RUNDIR)
    endif
    ifdef SUB
	for I in $(SUB);do ($(MAKE) -C $$I THIS_SUB=$$I install);done
    endif
