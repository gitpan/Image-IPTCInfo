# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..3\n"; }
END {print "package load...  not ok 1\n" unless $loaded;}
use Image::IPTCInfo;
$loaded = 1;
print "package load....  ok 1\n";

######################### End of black magic.

#
# Test loading IPTC info
#

my $info = new Image::IPTCInfo('demo_images/burger_van.jpg');

if (defined($info) && $info->Attribute('caption/abstract') eq
	'A van full of burgers awaits mysterious buyers in a dark parking lot.')
{
	print "get caption....   ok 2\n";
}
else
{
	print "get caption....   not ok 2\n";
	print "error: " . Image::IPTCInfo::Error() . "\n";
}

#
# Test saving IPTC info
#

$info->SetAttribute('caption/abstract', 'modified caption');
$info->SaveAs('demo_images/burger_van_save1.jpg') ||
	print "error: " . Image::IPTCInfo::Error() . "\n";

undef $info;

$info = new Image::IPTCInfo('demo_images/burger_van_save1.jpg');

if (defined($info) && $info->Attribute('caption/abstract') eq 'modified caption')
{
	print "save and load.... ok 3\n";
}
else
{
	print "save and load.... not ok 3\n";
	print "error: " . Image::IPTCInfo::Error() . "\n";
}

