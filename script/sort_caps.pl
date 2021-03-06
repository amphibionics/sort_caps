#!/usr/bin/perl


use strict;
use Getopt::Long;
use File::Path;
use File::Copy;
use Data::Dumper;


######################################################################
# DEFINE GLOBAL VARS
######################################################################
my $script = 'sort_caps.pl';
my $rev = '0.1';

my %opt;
my $log;
my @opt_files;
# my $date = `date`; chomp($date);
# my $user = `echo \$USER`; chomp($user);
my $date = "NOW";
my $user = "RRITA";
my $bound = '---------------------------------------------------------------';

my $supply = "vss! vcc! vss vcc 0 sgnd spwr vccpg vccm vccr";

my $logheader = <<"EOF";
########################################################################
# NETLIST CAPACITANCE AUDIT TOOL
# Log file generated by $script revision $rev.
#
# USER: $user
# DATE: $date
########################################################################
EOF

my @opts = @ARGV;

Getopt::Long::config ("no_auto_abbrev","no_pass_through");
if (! GetOptions (
                  "o=s"			=> \$opt{o},
                  "sort=s"		=> \$opt{s}, #value, node1, node2
                  "above=s"		=> \$opt{a},
                  "below=s"		=> \$opt{b},
                  "include=s"		=> \$opt{i},
                  "exclude=s"		=> \$opt{x},
                  "list=s"		=> \$opt{l},
                  "aggregate"		=> \$opt{ag},
                  "nosupply"		=> \$opt{ns},
                  "noaggsupply"		=> \$opt{as},
                  "brief"		=> \$opt{bf},
                  "h|help"		=> \&USAGE,
                  "<>"			=> \&PARAMETER,
                  )) { ERROR('[ERROR 00A]Invalid parameter') }


######################################################################
# MAIN
######################################################################

MAIN();
exit(0);


######################################################################
# SUB MAIN
######################################################################

#CREATE AND POPULATE PWR WORKAREA DIR...
sub MAIN {

	foreach my $file (@opt_files) {
		$log = GET_NAME($file);
		if (-e $log) {unlink($log)}
		open(LOG, ">$log") or ERROR("[ERROR 01A] CAN'T OPEN FILE $log");
		ECHO($logheader);
		ECHO(" [INFO] COMMAND: sort_caps.pl @opts");
		ECHO($bound);
		
		LOG("CAP NAME, NODE1, NODE2, CAP VALUE\n") if !$opt{ag};
		
		PARSE_SPF($file);
		close(LOG);
		DEBUGGER("\n [INFO] LOG FILE CREATED: $log ...");
		DEBUGGER("\n [INFO] DONE! ...");
	}
	
return;
}

######################################################################
# GET CAPS FROM SPF

sub PARSE_SPF {

my $file = shift;
my @list;
my %cap;
my $tmp;

#save input list to an array
if ($opt{l}) {
	open(LIST, "<$opt{l}") or ERROR("[ERROR 02A] CAN'T OPEN $opt{l}");
	while (<LIST>) { chomp(); push@list, $_ }
	close(LIST);
}

DEBUGGER("\n [INFO] EXTRACTING NETLIST CAPACITANCE ...");
open(IN, "<$file") or ERROR("[ERROR 02B] CAN'T OPEN $file");

#hash all capacitance
while (<IN>) {
	my $line = $_;
	if (/^\s*C(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s*$/i) {
	     my ($cname, $node1, $node2, $cval) = ($1, $2, $3, $4);

		if ($opt{ns}){$opt{x} = $supply}
		
		if (($opt{a})&&($cval < $opt{a})&&(!$opt{ag})) { next }
		elsif (($opt{b})&&($cval > $opt{b})&&(!$opt{ag})) { next }
		elsif ($opt{l}&&(!$opt{ag})) {
			for (@list) { if($line =~ /$_/i) { $cap{$cname}{$node1}{$node2} = $cval }}
		}
		elsif ($opt{x}) {
			my $flg;
			for (split/\s+/, $opt{x}){ if ($line =~ /$_/i){ $flg=1 } }
			if ($flg) {
				if ($opt{i}) {
					my $flg;
					for (split/\s+/, $opt{i}){ if ($line =~ /$_/i){ $flg=1 } }
					if ($flg) { { $cap{$cname}{$node1}{$node2} = $cval } }
					else { next } 
				}
				else { next }
			}
			else { { $cap{$cname}{$node1}{$node2} = $cval } }
		}
		else { $cap{$cname}{$node1}{$node2} = $cval }
	}
}
close(IN);


DEBUGGER("\n [INFO] CONCATENATE CAPACITANCE LIST ...");
#concatenate %cap hash
for my$cname (sort {$a <=> $b} keys %cap) {
	for my$node1 (keys %{$cap{$cname}}) {
		for my$node2 (keys %{$cap{$cname}{$node1}}) {
			my$cval = $cap{$cname}{$node1}{$node2};
			$tmp .= "C$cname,$node1,$node2,$cval\n";
		}
	}
}


#-aggregate option is here
if ($opt{ag}) { GET_AGG(\%cap) }
elsif ($opt{s} && !$opt{ag}) { RAW_SORTING($tmp) }
else {LOG($tmp)}


return;
}


######################################################################
# CALCULATE FOR AGGREGATE CAPACITANCE

sub GET_AGG {

my $capref = shift;
my %cap = %{$capref};
my %agg;
my %sorted;

	DEBUGGER("\n [INFO] COLLECTING AGGREGATE CAPS ...");
	LOG("REFERENCE NET, AGGREGATE CAPS, RELATED NETS/ASSUMED AGGRESSOR, CAP VALUE");
	
	#put all values in %agg hash
	for my$cname (keys %cap) {
		for my$node1 (keys %{$cap{$cname}}) {
			for my$node2 (keys %{$cap{$cname}{$node1}}) {
				$agg{$node1}{$node2} .= "$cap{$cname}{$node1}{$node2} ";
				$agg{$node2}{$node1} .= "$cap{$cname}{$node1}{$node2} ";
			}
		}
	}
	
	#rehash all values for the reference nets
	for my$ref (keys %agg) {
		my($val,$sum,$total);
		
		#calculate the total capacitance for each reference nets
		for my$net (keys %{$agg{$ref}}) {
			$val = $agg{$ref}{$net};
			#get the total caps in case where a $ref and $net combination yields multiple value
			if ($val =~ /\S+\s+\S+/){ 
				for (split/\s+/, $val) {$sum += $_}
				$val = $sum;
			}
			$total += $val;
		}
		#this is where rehashing of reference nets were done!
		$sorted{$ref} = $total;
	}
	
	# sorting reference nets based on their capacitance value
	for my$ref (sort {$sorted{$b} <=> $sorted{$a}} keys %sorted) {
		#debug disruption flag
		##if ($ref =~ /cib_ad/){ last }
	
		if ($opt{bf}) { LOG("$ref,$sorted{$ref}"); next } #display the total aggregate caps only
		
		my($flg,$cat,$val);
		if (($opt{a})&&($sorted{$ref} < $opt{a})) { next } #-above option: filter in all caps above the value set
		elsif (($opt{b})&&($sorted{$ref} > $opt{b})) { next } #-below option: filter in all caps below the value set
		
		if ($opt{as}) {for (split/\s+/, $supply){ if ($ref =~ /$_/i){ $flg=1 } }} #-noaggsupply option: skipping supply nets
		if ($flg) { next }
		
		my %relsorted;
		my %lastsort;
		# sorting related nets/assumed aggressor based on the reference net previously sorted
		for my$net (sort keys %{$agg{$ref}}) {
			my $fixnet;
			$val = $agg{$ref}{$net};
			
			#check for related bus
			if ($net =~ /(\S+)<\d+>/) { $fixnet = $1 }
			else { $fixnet = $net }
			
			#rehash with $fixnet as hash reference
			$relsorted{$fixnet}{$net} = $val;
		}
		
		#sort identified fixed nets
		for my$fixnet (sort keys %relsorted) {
			my $topval;
			for my$net (sort {$relsorted{$fixnet}{$b} <=> $relsorted{$fixnet}{$a}} keys %{$relsorted{$fixnet}}) {
				$topval = $relsorted{$fixnet}{$net}; last; #get the highest value for each fix net group
			}
			for my$net (sort {$relsorted{$fixnet}{$b} <=> $relsorted{$fixnet}{$a}} keys %{$relsorted{$fixnet}}) {
				$val = $relsorted{$fixnet}{$net};
				$lastsort{$topval}{$net} = $val; #rehash with the highest value as reference
			}
		}
		
		#sort with the highest value reference
		for my$topval (sort {$b <=> $a} keys %lastsort) {
			for my$net (sort {$lastsort{$topval}{$b} <=> $lastsort{$topval}{$a}} keys %{$lastsort{$topval}}) {
				$cat .= "$ref, ,$net,$lastsort{$topval}{$net}\n";
			}
		}
		
		#print all processed data
		my $total = $sorted{$ref};
		LOG("$ref,$total,[aggregate lines]");
		print LOG "$cat";
	}

return;
}


######################################################################
# SORT RAW CAPACITANCE LIST DATA

sub RAW_SORTING {

my $tmp = shift;
my $tmptxt = ".tmp.txt";

	open(TMP, ">$tmptxt"); print TMP $tmp; close(TMP);

	DEBUGGER("\n [INFO] SORTING RAW CAPACITANCE LIST ...");
	#sorting capacitance value without aggregate calculation
	if ($opt{s} =~ /^value/i) {
		DEBUGGER("\n [INFO] SORTING CAPACITANCE VALUE ...");
		# `less $tmptxt | sort -g -t, -k4 -r >> $log`
	}
	#sorting assumed aggressor nets without aggregate calculation
	elsif ($opt{s} =~ /^node2/i) {
		DEBUGGER("\n [INFO] SORTING NODE2 ...");
		# `less $tmptxt | sort -t, -k3 >> $log`
	}
	#sorting reference nets without aggregate calculation
	elsif ($opt{s} =~ /^node1/i) {
		DEBUGGER("\n [INFO] SORTING NODE1 ...");
		# `less $tmptxt | sort -t, -k2 >> $log`
	}
	else {LOG($tmp)}



return;
}











#=====================================================================
#=====================================================================
# UTILITY MODULES
#=====================================================================
#=====================================================================

######################################################################
# ERROR

sub ERROR {
	my $error = shift;
	print STDOUT "%Error: $error, try \'$script --help\'\n\n";
	
	exit (1);
}

######################################################################
# DEBUGGER

sub DEBUGGER { print STDOUT "@_\n"; return }

######################################################################
# DUMPER

sub DUMPER { print Dumper @_; return }

######################################################################
# ECHO

sub ECHO { print STDOUT "@_\n"; print LOG "@_\n"; return }

######################################################################
# LOG

sub LOG { print LOG "@_\n"; return }

######################################################################
# WRONG OPTION

sub PARAMETER {
        my $param = shift;
        if ($param =~ /^--?/) { die "Unknown parameter: $param\n" }     #filter out correct options
        else { push @opt_files, "$param" }                              # Must quote to convert Getopt to string
return;

}

######################################################################
# MANAGE NAMING

sub GET_NAME {
        my $file = shift;
        my $out;
        if (!$opt{o}) { $file =~ s/^.*\///g; $out = "$file".".cap.csv" }
        else {$out = $opt{o}}                                            #setting the correct filename

return $out;
}

######################################################################
######################################################################
######################################################################
######################################################################

# HELP

sub USAGE {

print <<EOH;
--------------------------------------------------------------------------------------------------------
DESCRIPTION
        $script - A tool that extracts and sorts netlist capacitance from an input parasitics(.SPF) file format.

        Default output filename: "<SPF file>.cap.log"

USAGE
        $script <.spf file> [option]

OPTION
        Required:
        <.spf file>			Input .SPF parasitics file
					Please use -rctype cc during LPE extraction

        Optional:
        -sort [value|node1|node2] 	Will sort according to category
	-above [value]			filters in data above this cap value
	-below [value]			filters in data below this cap value
	-include [string]		filters in data containing this string, accepts white-space separated array
	-exclude [string]		filters out data containing this string, accepts white-space separated array
	-list [list file]		filters in data contained in the list file 
        -aggregate			report total capacitance for each net names
        -nosupply			remove supply nets from capacitance list
        -noaggsupply			remove supply reference nets from total aggregate counts
	-o [file name]			desired output file name
        -h|help                         display help message

EXAMPLES
        1. %> sort_caps.pl ebr_RCmax_cc_85C.spf -aggregate
                -This generate list of nets together with related nets and values

        2. %> sort_caps.pl ebr_RCmax_cc_85C.spf -aggregate -nosupply
                -Same as the first example but all supply nets were removed from capacitance list

        3. %> sort_caps.pl ebr_RCmax_cc_85C.spf -aggregate -noaggsupply
                -Same as the first example but all supply nets were removed from the total aggregate counts

        4. %> sort_caps.pl ebr_RCmax_cc_85C.spf -aggregate -above 10e-15
                -Same as the first example but all below 10e-15 aggregate values will not be counted in the list

        5. %> sort_caps.pl ebr_RCmax_cc_85C.spf -sort value
                -This will extract netlist capacitance and will sort capacitance value in decending order

        6. %> sort_caps.pl ebr_RCmax_cc_85C.spf -sort value -above 0.5e-15
                -This will exclude those with caps value below 0.5e-15

        7. %> sort_caps.pl ebr_RCmax_cc_85C.spf -sort value -exclude vcc
                -This will exclude those with "vcc" node name

        8. %> sort_caps.pl ebr_RCmax_cc_85C.spf -sort value -exclude "vcc vss" -include "por cib"
                -This will exclude those with "vcc"  and "vss" node names except for those with "por" and "cib" node names


list file example:
-------------------
vcc
vss
gnd
-------------------

SCOPE AND LIMITATIONS
        1. Supports capacitance extraction for .SPF file only.

REVISION HISTORY:
        1. 12/01/15[rrita] -initial version
--------------------------------------------------------------------------------------------------------
EOH
exit(1);
}

__END__
