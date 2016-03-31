#!/usr/bin/perl

use Encode qw/encode decode/;
use strict;

my $progname = $0; $progname =~ s@^.*/@@;

# accept path of bogued "link" file on command line
my $file = shift()
  or die "$progname: usage: $progname <file>\n";

# check valid number of characters of input string
my $strlen = length $file;

if ($strlen <=2)
{
    print "$progname: $file is not a file\n";
    exit 0;
} 

# read the bogued file to find out where the symlink should point
my $content = '';
my $target = '';

open my $fh, '<', $file
  or die "$progname: unable to open $file: $!\n";

# parse the target path out of the file content
$content = <$fh>;

if (!($content =~ m@!<symlink>..(.*)@)) {
    #print "$progname: $file content in bogus format\n";
    print ".";
    exit 0;
}

$target = $1;
$target = decode("UCS-2LE", $target);

close $fh;


# delete the bogued file
my $oldname = $file.".previously-symlink";
unlink $oldname;

rename $file,$oldname;

# replace it with the correct symlink
system('ln', '-s', $target, $file);
print "\n$progname: fixed $file\n";

