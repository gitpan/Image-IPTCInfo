#!/usr/bin/perl

# IPTCInfo: extractor for IPTC metadata embedded in images
# Copyright (C) 2000 Josh Carter <josh@spies.com>
# All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.

package Image::IPTCInfo;

use vars qw($VERSION);
$VERSION = 1.1;

#
# Global vars
#
use vars ('%datasets',		# master list of dataset id's
		  '%listdatasets',	# master list of repeating dataset id's
		  '$debugMode',		# turns on diagnostic output
		  );

# Debug off for production use
$debugMode = 0;
		  
#####################################
# These names match the codes defined in ITPC's IIM record 2.
# This hash is for non-repeating data items; repeating ones
# are in %listdatasets below.
%datasets = (
#	0	=> 'record version',		# skip -- binary data
	5	=> 'object name',
	7	=> 'edit status',
	8	=> 'editorial update',
	10	=> 'urgency',
	12	=> 'subject reference',
	15	=> 'category',
#	20	=> 'supplemental category',	# in listdatasets (see below)
	22	=> 'fixture identifier',
#	25	=> 'keywords',				# in listdatasets
	26	=> 'content location code',
	27	=> 'content location name',
	30	=> 'release date',
	35	=> 'release time',
	37	=> 'expiration date',
	38	=> 'expiration time',
	40	=> 'special instructions',
	42	=> 'action advised',
	45	=> 'reference service',
	47	=> 'reference date',
	50	=> 'reference number',
	55	=> 'date created',
	60	=> 'time created',
	62	=> 'digital creation date',
	63	=> 'digital creation time',
	65	=> 'originating program',
	70	=> 'program version',
	75	=> 'object cycle',
	80	=> 'by-line',
	85	=> 'by-line title',
	90	=> 'city',
	92	=> 'sub-location',
	95	=> 'province/state',
	100	=> 'country/primary location code',
	101	=> 'country/primary location name',
	103	=> 'original transmission reference',
	105	=> 'headline',
	110	=> 'credit',
	115	=> 'source',
	116	=> 'copyright notice',
	118	=> 'contact',
	120	=> 'caption/abstract',
	122	=> 'writer/editor',
#	125	=> 'rasterized caption', # unsupported (binary data)
	130	=> 'image type',
	131	=> 'image orientation',
	135	=> 'language identifier',
	);

%listdatasets = (
	20	=> 'supplemental category',
	25	=> 'keywords',
	);
	
#######################################################################
# New, Destroy
#######################################################################

#
# new
# 
# $info = new IPTCInfo('image filename goes here')
# 
# Returns iPTCInfo object filled with metadata from the given image 
# file. File on disk will be closed, and changes made to the IPTCInfo
# object will *not* be flushed back to disk.
#
sub new
{
	my ($pkg, $filename) = @_;

	#
	# Open file and snarf data from it.
	#
	open(FILE, $filename) || return undef;

	binmode(FILE);

	unless (my $offset = ScanToFirstIMMTag())
	{
		Log("No IPTC data found. Bailing out");
		return undef;
	}

	my $self = bless
	{
		'_data'		=> {},	# empty hashes; wil be
		'_listdata'	=> {},	# filled in CollectIIMInfo
	}, $pkg;
	
	# Do the real snarfing here
	CollectIIMInfo($self);
	
	close(FILE);
		
	return $self;
}

#
# DESTROY
# 
# Called when object is destroyed. No action necessary in this case.
#
sub DESTROY
{
	# no action necessary
}

#######################################################################
# Attributes for clients
#######################################################################

#
# Attribute
# 
# Returns value of a given data item.
#
sub Attribute
{
	my ($self, $attribute) = @_;

	return $self->{_data}->{$attribute};
}

#
# Keywords
# 
# Returns reference to a list of keywords.
#
sub Keywords
{
	my $self = shift;
	
	return $self->{_listdata}->{'keywords'};
}

#
# SupplementalCategories
# 
# Returns reference to a list of supplemental categories.
#
sub SupplementalCategories
{
	my $self = shift;
	
	return $self->{_listdata}->{'supplemental category'};
}

#
# ExportXML
# 
# $xml = $info->ExportXML('entity-name', \%extra-data,
#                         'optional output file name');
# 
# Exports XML containing all image metadata. Attribute names are
# translated into XML tags, making adjustments to spaces and slashes
# for compatibility. (Spaces become underbars, slashes become dashes.)
# Caller provides an entity name; all data will be contained within
# this entity. Caller optionally provides a reference to a hash of 
# extra data. This will be output into the XML, too. Keys must be 
# valid XML tag names. Optionally provide a filename, and the XML 
# will be dumped into there.
#
sub ExportXML
{
	my ($self, $basetag, $extraRef, $filename) = @_;
	my $out;
	
	$basetag = 'photo' unless length($basetag);
	
	$out .= "<$basetag>\n";

	# dump extra info first, if any
	foreach my $key (keys %$extraRef)
	{
		$out .= "\t<$key>" . $extraRef->{$key} . "</$key>\n";
	}
	
	# dump our stuff
	foreach my $key (keys %{$self->{_data}})
	{
		my $cleankey = $key;
		$cleankey =~ s/ /_/g;
		$cleankey =~ s/\//-/g;
		
		$out .= "\t<$cleankey>" . $self->{_data}->{$key} . "</$cleankey>\n";
	}
	
	if (defined ($self->Keywords()))
	{
		# print keywords
		$out .= "\t<keywords>\n";
		
		foreach my $keyword (@{$self->Keywords()})
		{
			$out .= "\t\t<keyword>$keyword</keyword>\n";
		}
		
		$out .= "\t</keywords>\n";
	}

	if (defined ($self->SupplementalCategories()))
	{
		# print supplemental categories
		$out .= "\t<supplemental_categories>\n";
		
		foreach my $category (@{$self->SupplementalCategories()})
		{
			$out .= "\t\t<supplemental_cagegory>$category</supplemental_category>\n";
		}
		
		$out .= "\t</supplemental_categories>\n";
	}

	# close base tag
	$out .= "</$basetag>\n";

	# export to file if caller asked for it.
	if (length($filename))
	{
		open(XMLOUT, ">$filename");
		print XMLOUT $out;
		close(XMLOUT);
	}
	
	return $out;
}

#
# ExportSQL
# 
# my %mappings = (
#   'IPTC dataset name here'    => 'your table column name here',
#   'caption/abstract'          => 'caption',
#   'city'                      => 'city',
#   'province/state'            => 'state); # etc etc etc.
# 
# $statement = $info->ExportSQL('mytable', \%mappings, \%extra-data);
#
# Returns a SQL statement to insert into your given table name 
# a set of values from the image. Caller passes in a reference to
# a hash which maps IPTC dataset names into column names for the
# database table. Optionally pass in a ref to a hash of extra data
# which will also be included in the insert statement. Keys in that
# hash must be valid column names.
#
sub ExportSQL
{
	my ($self, $tablename, $mappingsRef, $extraRef) = @_;
	my ($statement, $columns, $values);
	
	return undef if (($tablename eq undef) || ($mappingsRef eq undef));

	# start with extra data, if any
	foreach my $column (keys %$extraRef)
	{
		my $value = $extraRef->{$column};
		$value =~ s/'/''/g; # escape single quotes
		
		$columns .= $column . ", ";
		$values  .= "\'$value\', ";
	}
	
	# process our data
	foreach my $attribute (keys %$mappingsRef)
	{
		my $value = $self->Attribute($attribute);
		$value =~ s/'/''/g; # escape single quotes
		
		$columns .= $mappingsRef->{$attribute} . ", ";
		$values  .= "\'$value\', ";
	}
	
	# must trim the trailing ", " from both
	$columns =~ s/, $//;
	$values  =~ s/, $//;

	$statement = "INSERT INTO $tablename ($columns) VALUES ($values)";
	
	return $statement;
}

#######################################################################
# File parsing functions (private)
#######################################################################

#
# ScanToFirstIMMTag
#
# Scans to first IIM Record 2 tag in the file. Expects to see this tag
# within the first 512 bytes of data. (This limit may need to be changed
# or eliminated depending on how other programs choose to store IIM.)
#
sub ScanToFirstIMMTag
{
	my $offset = 0;
	my $MAX    = 512; # keep within first 512 bytes 
					  # NOTE: this may need to change
	
	# reset to beginning just in case
	seek(FILE, 0, 0);
		
	# start digging
	while ($offset <= $MAX)
	{
		my $temp;
		
		read(FILE, $temp, 1);

		# look for tag identifier 0x1c
		if (ord($temp) == 0x1c)
		{
			# if we found that, look for record 2, dataset 0
			# (record version number)
			my $record, $dataset;
			read (FILE, $record, 1);
			read (FILE, $dataset, 1);
			
			if (ord($record) == 2 && ord($dataset) == 0)
			{
				# found it. seek to start of this tag and return.
				seek(FILE, $offset, 0);
				return $offset;
			}
			else
			{
				# didn't find it. back up 2 to make up for
				# those reads above.
				seek(FILE, $offset + 1, 0);
			}
		}

		# for debugging only: hex dump data as we scan it
		# my $hex = unpack("H*", $temp);
		# print " " . $hex;
		
		# no tag, keep scanning
		$offset++;
	}
	
	return 0;
}


#
# CollectIIMInfo
#
# Assuming file is seeked to start of IIM data (using above), this
# reads all the data into our object's hashes
#
sub CollectIIMInfo
{
	my $self = shift;
	
	# NOTE: file should already be at the start of the first
	# IPTC code: record 2, dataset 0.
	
	while (true)
	{
		my $header;
		read(FILE, $header, 5);
		
		($tag, $record, $dataset, $length) = unpack("CCCn", $header);

		# bail if we're past end of IIM record 2 data
		return unless ($tag == 0x1c) && ($record == 2);
		
		# print "tag     : " . $tag . "\n";
		# print "record  : " . $record . "\n";
		# print "dataset : " . $dataset . "\n";
		# print "length  : " . $length  . "\n";
	
		my $value;
		read(FILE, $value, $length);
		
		# try to extract first into _listdata (keywords, categories)
		# and, if unsuccessful, into _data. Tags which are not in the
		# current IIM spec (version 4) are currently discarded.
		if (exists $listdatasets{$dataset})
		{
			my $dataname = $listdatasets{$dataset};
			my $listref  = $listdata{$dataname};
			
			push(@{$self->{_listdata}->{$dataname}}, $value);
		}
		elsif (exists $datasets{$dataset})
		{
			my $dataname = $datasets{$dataset};
	
			$self->{_data}->{$dataname} = $value;
		}
		# else discard
	}
}

#
# Log: just prints a message to STDERR if $debugMode is on.
#
sub Log
{
	if ($debugMode)
	{
		my $message = shift;
		my $oldFh = select(STDERR);
	
		print "**IPTC** $message\n";
		
		select($oldFh);
	}
} 

# sucessful package load
1;

__END__

=head1 NAME

Image::IPTCInfo - Perl extension for extracting IPTC image meta-data

=head1 SYNOPSIS

  use Image::IPTCInfo;

  # Create new info object
  my $info = new Image::IPTCInfo('file-name-here.jpg');
    
  # Get list of keywords...
  my $keywordsRef = $info->Keywords();
    
  # Get specific attributes...
  my $caption = $info->Attribute('caption/abstract');
    
  # ...and so forth.

=head1 DESCRIPTION

Ever wish you add information to your photos like a caption, the place
you took it, the date, and perhaps even keywords and categories? You
already can. The International Press Telecommunications Council (IPTC)
defines a format for exchanging meta-information in news content, and
that includes photographs. You can embed all kinds of information in
your images. The trick is putting it to use.

That's where this IPTCInfo Perl module comes into play. You can embed
information using many programs, including Adobe Photoshop, and
IPTCInfo will let your web server -- and other automated server
programs -- pull it back out. You can use the information directly in
Perl programs, export it to XML, or even export SQL statements ready
to be fed into a database.

=head1 USING IPTCINFO

Install the module as documented in the README file. You can try out
the demo program called "demo.pl" which extracts info from the images
in the "demo-images" directory.

To integrate with your own code, simply do something like what's in
the synopsys above.

The complete list of possible attributes is given below. These are as
specified in the IPTC IIM standard, version 4. Keywords and categories
are handled differently: since these are lists, the module allows you
to access them as Perl lists. Call Keywords() and Categories() to get
a reference to each list.

=head1 XML AND SQL EXPORT FEATURES

IPTCInfo also allows you to easily generate XML and SQL from the image
metadata. For XML, call:

  $xml = $info->ExportXML('entity-name', \%extra-data,
                          'optional output file name');

This returns XML containing all image metadata. Attribute names are
translated into XML tags, making adjustments to spaces and slashes for
compatibility. (Spaces become underbars, slashes become dashes.) You
provide an entity name; all data will be contained within this entity.
You can optionally provides a reference to a hash of extra data. This
will get put into the XML, too. (Example: you may want to put info on
the image's location into the XML.) Keys must be valid XML tag names.
You can also provide a filename, and the XML will be dumped into
there. See the "demo.pl" script for examples.

For SQL, it goes like this: 

  my %mappings = (
       'IPTC dataset name here' => 'your table column name here',
       'caption/abstract'       => 'caption',
       'city'                   => 'city',
       'province/state'         => 'state); # etc etc etc.
    
  $statement = $info->ExportSQL('mytable', \%mappings, \%extra-data);

This returns a SQL statement to insert into your given table name a
set of values from the image. You pass in a reference to a hash which
maps IPTC dataset names into column names for the database table. As
with XML export, you can also provide extra information to be stuck
into the SQL.

=head1 IPTC ATTRIBUTE REFERENCE

  object name               originating program              
  edit status               program version                  
  editorial update          object cycle                     
  urgency                   by-line                          
  subject reference         by-line title                    
  category                  city                             
  fixture identifier        sub-location                     
  content location code     province/state                   
  content location name     country/primary location code    
  release date              country/primary location name    
  release time              original transmission reference  
  expiration date           headline                         
  expiration time           credit                           
  special instructions      source                           
  action advised            copyright notice                 
  reference service         contact                          
  reference date            caption/abstract                 
  reference number          writer/editor                    
  date created              image type                       
  time created              image orientation                
  digital creation date     language identifier
  digital creation time

=head1 KNOWN BUGS

IPTC meta-info on MacOS may be stored in the resource fork instead
of the data fork. This program will currently not scan the resource
fork.

Some programs will embed IPTC info at the end of the file instead of
the beginning. The module will currently only look near the front of
the file. You can change this behavior in ScanToFirstIMMTag if needed.
Future versions should be smarter about scanning JPGs for this info.

IPTCInfo can't modify your images, i.e. adding or changing the info in
them. Some day it will.

=head1 AUTHOR

Josh Carter, josh@multipart-mixed.com

=head1 SEE ALSO

perl(1).

=cut
