#!/usr/bin/env perl
# This script will read in a map file generated by the GNU linker
# and generate a list of text segments that will fit in the specified space
# It is used to work around the fact that ld cannot handle a hole in a section, and
# to pack object files around the CRC code which must be located at a specific address
use Data::Dumper;
use Getopt::Long;

my %map;
my $free = 0;
my $mapfile;
my $linkfile;
GetOptions("mapfile=s" => \$mapfile, "linkfile=s" => \$linkfile, "size=o" => \$free);
if (! $free && $linkfile) {
    $free = extract_crcoffset_from_linkfile($linkfile);
}
read_map($mapfile);
repack_obj();

sub fix_obj_name {
    my($obj) = @_;
    if($obj =~ /^(\S+)\((\S+)\)/) {
        return "$1:$2";
    }
    return $obj;
}

sub repack_obj {
    my @sorted  = sort {$map{$b} <=> $map{$a}} keys(%map);
    foreach (@sorted) {
        if($free >= $map{$_}) {
            $free -= $map{$_};
            printf "\t%-32s (.text*) /* 0x%x */\n", fix_obj_name($_), $map{$_};
        }
    }
    printf "/* Remaining space: 0x%x */\n", $free;
}

sub read_map {
    my($file) = @_;
    open my $fh, "<", $file or die("Can't read $file\n");
    my $start = 0;
    my $lastfile = "";
    while(<$fh>) {
        s/\r//;
        if(! $start) {
           $start = 1 if(/Linker script and memory map/);
           next;
        }
        if(/^\s*\.vectors\s+\S+\s+(\S+)/) {
            $free -= hex($1);
        }
        if(/^\s+\.text/) {
            if(! /0x/) {
                chomp;
                $_ .= <$fh>;
                s/\r//;
            }
            chomp;
            my($address, $obj) = (/^\s+\S+\s+(\S+)\s.*\s(\S+)$/);
            $address = hex($address);
            if($obj ne $lastobj) {
                $map{$lastobj} = $address - $objstart if($lastobj);
                $lastobj = $obj;
                $objstart = $address;
            }
        } elsif(/\. = ALIGN/) {
            my($address) = (/^\s+(\S+)/);
            $address = hex($address);
            $map{$lastobj} = $address - $objstart;
        #} elsif(/\s+\.(debug_\S+|comment|ARM.attributes)/) {
        #    if(! / 0x/) {
        #        chomp;
        #        $_ .= <$fh>;
        #    }
        #    if(/\s+\.\S+\s+\S+\s+(\S+)\s+(\S+)$/) {
        #        $map{$2} += hex($1);
        #    }
        }
    }
}
sub read_linkfile {
    my($file) = @_;
    open my $fh, "<", $file;
    my @lines = <$fh>;
    close $fh;
    my @final;
    for my $line (@lines) {
        if($line =~ /^\s*INCLUDE\s+(\S+)/) {
            push @final, read_linkfile($1);
        } else {
            push @final, $line;
        }
    }
    return @final;
}
sub extract_crcoffset_from_linkfile {
    my($file) = @_;
    my @lines = read_linkfile($file);
    for (@lines) {
        if (/^\s*_crc_offset\s*=\s*([0-9xX]+);/) {
            return hex($1);
        }
    }
    return 0;
}
