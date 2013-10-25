#!/usr/bin/env perl

use strict;
use warnings;

if ($#ARGV != 0 )
{
    print STDERR "usage: mask_friston_motion.pl <1D file> $#ARGV\n";
    exit(1);
}

open( INFILE, "<$ARGV[0]" ) or die "Could not open $ARGV[0] for reading\n";

my @prev_motion=(0.0,0.0,0.0,0.0,0.0,0.0);
my $linecount = 0;
while( <INFILE> )
{
    # skip comments
    if($_ =~ "#")
    {
        print STDERR "Line $_ contains comment\n";
    }
    else
    {
        chomp();
        $_=~s/^\s+//g;
        my @current_motion=split(/\s+/,$_);

        my $nmotion=scalar(@current_motion);
        if( $nmotion == 6 )
        {
            print "  $current_motion[0]"; 
            for( my $i=1; $i<$nmotion; $i++ )
            {
                print "   $current_motion[$i]"; 
            }
            for( my $i=0; $i<$nmotion; $i++ )
            {
                my $t = $current_motion[$i]*$current_motion[$i];
                print "   $t"; 
            }
            for( my $i=0; $i<$nmotion; $i++ )
            {
                print "   $prev_motion[$i]"; 
            }
            for( my $i=0; $i<$nmotion; $i++ )
            {
                my $t = $prev_motion[$i]*$prev_motion[$i];
                print "   $t"; 
            }
            for( my $i=0; $i<$nmotion; $i++ )
            {
                $prev_motion[$i]=$current_motion[$i];
            }
            print "\n";
        }
        else
        {
            print STDERR "Line $linecount has the wrong number of motion parameters ($nmotion != 6)\n"
        }
    }
    $linecount++;
};


close( INFILE );
exit(0);

