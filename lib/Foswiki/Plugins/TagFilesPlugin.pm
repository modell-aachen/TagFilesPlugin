# See bottom of file for default license and copyright information


package Foswiki::Plugins::TagFilesPlugin;

use strict;
use warnings;

use Foswiki::Func    ();    # The plugins API
use Foswiki::Plugins ();    # For the API version

our $VERSION          = '$Rev: 7808 (2010-06-15) $';
our $RELEASE          = '0.0.1';

our $SHORTDESCRIPTION = 'Tag files in your wiki.';

our $NO_PREFS_IN_TOPIC = 1;


sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 2.0 ) {
        Foswiki::Func::writeWarning( 'Version mismatch between ',
            __PACKAGE__, ' and Plugins.pm' );
        return 0;
    }

    # Copy/Paste/Modify from MetaCommentPlugin
    # SMELL: this is not reliable as it depends on plugin order
    # if (Foswiki::Func::getContext()->{SolrPluginEnabled}) {
    if ($Foswiki::cfg{Plugins}{SolrPlugin}{Enabled}) {
      require Foswiki::Plugins::SolrPlugin;
      Foswiki::Plugins::SolrPlugin::registerIndexAttachmentHandler(
        \&indexAttachmentHandler
      );
    }

    # Plugin correctly initialized
    return 1;
}

# Will add tags on file upload.
# See afterUploadHandler for "changeproperties" ("Change comment only");
sub beforeUploadHandler {
    my( $attrHashRef, $meta ) = @_;

    my $query = Foswiki::Func::getCgiQuery();
    my $tags = formatTags( $query->{param}->{tags} );
    $attrHashRef->{tags} = $tags if defined $tags;
}

# Format the taglist.
# With a proper select, or textboxlist this will actually do nothing.
sub formatTags {
    my ( $tagsParams ) = @_;

    return unless $tagsParams;

    my $tags = ();
    foreach my $tag ( @$tagsParams ) {
        $tag =~ s#^\s*##;
        $tag =~ s#\s*$##;
        next unless $tag;
        $tags->{$tag} = 1;
    }
    return unless scalar $tags;
    return join(',', keys $tags);
}

# Unfortunately "changeproperties" ("Change comment only") bypasses the
# beforeUploadHandler. When the afterUploadHandler is being called everything
# has been written to disc already, so we need to read it again and then save
# a second time.
sub afterUploadHandler {
    my( $attrHashRef, $meta ) = @_;

    my $query = Foswiki::Func::getCgiQuery();
    return unless $query->{param}->{changeproperties} && $query->{param}->{changeproperties}->[0];

    my $tags = formatTags( $query->{param}->{tags} ) || '';

    my $web = $meta->web();
    my $topic = $meta->topic();
    my ( $readmeta, $readtext ) = Foswiki::Func::readTopic( $web, $topic );
    my $file = $readmeta->get( 'FILEATTACHMENT', $attrHashRef->{attachment} );
    unless ( $file ) {
        return;
    }
    my $oldTags = $file->{tags} || '';
    return if $oldTags eq $tags;
    $file->{tags} = $tags;
    $readmeta->putKeyed( 'FILEATTACHMENT', $file );
    Foswiki::Func::saveTopic( $web, $topic, $readmeta, $readtext, {minor => 1, dontlog => 1, ignorepermissions => 1} );
}

sub indexAttachmentHandler {
    my ($indexer, $doc, $web, $topic, $attachment) = @_;

    if($attachment->{tags}) {
        my @taglist = split(',', $attachment->{tags});
        $doc->add_fields( attachment_tags_lst => \@taglist );
    }
}


1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Author: %$AUTHOR%

Copyright (C) 2008-2013 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
