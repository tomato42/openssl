#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /CoreOS/openssl/Regression/bz1090952-Do-not-send-ECC-ciphersuites-in-SSLv2-client-hello
#   Description: Test for BZ#1090952 (Do not send ECC ciphersuites in SSLv2 client hello)
#   Author: Hubert Kario <hkario@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2014 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

PACKAGE="openssl"
PACKAGES="openssl wireshark tcpdump"

rlJournalStart
    rlPhaseStartSetup
        rlAssertRpm --all
        rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
        rlRun "pushd $TmpDir"
        if grep 1 /proc/sys/crypto/fips_enabled; then
            rlLogInfo "Test requires SSLv2 which is disallowed in FIPS mode, aborting"
            rlPhaseEnd
            rlJournalPrintText
            rlJournalEnd
            exit 0
        fi
        rlRun "openssl req -x509 -newkey rsa:2048 -keyout server.key -out server.crt -subj /CN=localhost -nodes -batch" 0 "Create certificate"
        if rpm -q httpd; then
            rlServiceStop httpd
        fi
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "openssl s_server -key server.key -cert server.crt -www -accept 443 -no_ecdhe -no_dhe -cipher ALL > server.log 2> server.err &" 0 "Start s_server"
        server_pid=$!
        rlRun "tcpdump -i lo -s 0 -w capture.pcap port 443 &" 0 "Start tcpdump"
        tcpdump_pid=$!
        sleep 3
        rlRun "kill -s 0 $server_pid" 0 "Check if server is running"
        rlRun "kill -s 0 $tcpdump_pid" 0 "Check if tcpdump is running"
        rlRun "(echo -e 'GET / HTTP/1.0\n\n'; sleep 2 ) | openssl s_client -CAfile server.crt -cipher ALL -connect localhost:443 > client.log 2> client.err" 0 "Run client"
        rlRun "kill -s 15 $server_pid" 0 "Kill server"
        rlRun "kill -s 15 $tcpdump_pid" 0 "Kill tcpdump"
        rlRun "grep 'HTTP/1.0 200 ok' client.log" 0 "Check if client got response from server"
        rlRun "tshark -o 'ssl.desegment_ssl_records:TRUE' -o 'ssl.keys_list:0.0.0.0,443,http,server.key' -o 'ssl.debug_file:rsa_private.log' -r capture.pcap -V > capture.txt"
        rlAssertGrep "Version: SSL 2.0" capture.txt
        rlRun "grep -A 100 'Cipher Specs' capture.txt > cipher_suites.txt" 0 "Check if client offered cipher suites"
        rlAssertNotGrep "ECDH" "cipher_suites.txt"
        rlAssertNotGrep "ECDSA" "cipher_suites.txt"
        rlAssertGrep "SSL2_IDEA_128_CBC_WITH_MD5" "cipher_suites.txt"
        rlBundleLogs tshark-logs capture.txt rsa_private.log
        rlBundleLogs openssl-logs server.log server.err client.log client.err
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "popd"
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
        if rpm -q httpd; then
            rlServiceRestore httpd
        fi
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
