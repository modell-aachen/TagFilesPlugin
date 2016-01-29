# See bottom of file for default license and copyright information


package Foswiki::Plugins::TagFilesPlugin;

use strict;
use warnings;

use Foswiki::Func    ();    # The plugins API
use Foswiki::Plugins ();    # For the API version
use Error ':try';
use URI::Escape;

our $VERSION          = '0.0.6';
our $RELEASE          = '0.0.6';

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

    Foswiki::Func::registerRESTHandler(
        'bulkTag', \&_restBulkTag,
        http_allow => 'POST' );

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
    return join(',', keys %$tags);
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
        $doc->add_fields( attachment_tags_s => join(',', @taglist) );
    }
}

# Tag a bunch of files.
# The tags being set are expected in parameter 'tags' (comma separated list).
# If a file should be tagged it must send the keyword 'BulkTagUpdate' followed
# by the desired tags. The name should be web.topic/attachment with subwebs
# separated by dots (not slashes)
# For example:
# <input name='tags' value='Test,MyTag' />
# <input name='Main.SubWeb.MyTopic/MyFile.txt' value='BulkTagUpdate'/>
# <input name='Main.SubWeb.MyTopic/MyFile.txt' value='Test' />
# In this case the file MyFile.txt in Main/SubWeb/MyTopic will get the tag
# 'Test' but the tag 'MyTag' will be cleared. Any other tags will remain.
sub _restBulkTag {
    my ($session) = @_;

    my $query = Foswiki::Func::getCgiQuery();
    return unless $query;
    my $param = $query->{param};
    return unless $param;

    # get tags handled in this request
    my $tags = $param->{tags};
    return 'Wrong parameter "tags"' unless $tags && scalar @$tags == 1;
    my @tags = split( ',', $tags->[0] );
    @tags = map { my $t = $_; $t =~ s#^\s*|\s*$##; $t } @tags;

    my $backlink = $query->param( 'backlink' ) || '%WIKILOGOURL%';
    Foswiki::Func::setPreferencesValue( 'BACKLINK', $backlink );

    my $report = '';

    my $dirtyTopics = {}; # this will cache the changed topics in order to
                          # prevent multiple writes on multiple changes to a
                          # single topic

    foreach my $p ( keys %$param ) {
        my $values = $param->{ $p };
        next unless $values && scalar @$values;

        next unless shift( @$values ) eq 'BulkTagUpdate';

        # get web, topic and attachmentname from parameter
        my $webtopicattachment = uri_unescape($p);
        if( $webtopicattachment ne $p && $Foswiki::UNICODE ) {
            $webtopicattachment = Foswiki::Store::decode( $webtopicattachment );
        }
        unless ( $webtopicattachment =~ m#([^/]+)/(.*)# ) {
            $report .= '%BR%%MAKETEXT{"bad attachment name: [_1]" args="'."$webtopicattachment\"}%";
            next;
        }
        my $webtopic = $1;
        my $attachment = $2;
        my ( $web, $topic ) = Foswiki::Func::normalizeWebTopicName( undef, $webtopic );

        # read topic
        my ( $meta, $text );
        { # scope
            my $cached = $dirtyTopics->{"$web.$topic"};
            if ( $cached ) {
                ( $meta, $text ) = @$cached;
            } else {
                unless ( Foswiki::Func::topicExists( $web, $topic ) ) {
                    $report .= '%BR%%MAKETEXT{"Topic does not exist: [_1] with attachment: [_2]" args="'."$web.$topic,$attachment\"}%";
                    next;
                }
                ( $meta, $text ) = Foswiki::Func::readTopic( $web, $topic );
            }
        }

        # get current file tags
        my $file = $meta->get( 'FILEATTACHMENT', $attachment );
        unless ( $file ) {
            $report .= '%BR%%MAKETEXT"File not found: [_1]" args="'."$web.$topic/$attachment\"}%";
            next;
        }
        my $filetags = $file->{tags} || '';

        # check for changed tags
        my $dirty = 0;
        foreach my $eachTag ( @tags ) {
            # is $eachTag requested to be set?
            my $setTag = 0;
            foreach my $handeledTag ( @$values ) {
                $setTag = 1 if $handeledTag eq $eachTag;
            }

            # is $eachTag already set in file?
            my $hasTag = ($filetags =~ m#\Q$eachTag\E#)?1:0;

            next if $hasTag eq $setTag;

            if ( $setTag ) {
                # add $eachTag
                $filetags .= ',' if $filetags;
                $filetags .= $eachTag;
            } else {
                # remove $eachTag
                $filetags =~ s#,\Q$eachTag\E,#,#;
                $filetags =~ s#^\Q$eachTag\E,##;
                $filetags =~ s#,\Q$eachTag\E$##;
                $filetags =~ s#^\Q$eachTag\E$##;
            }
            # this attachment has changed
            $dirty = 1;
        }

        # only mark for save if tags actually changed
        if ( $dirty ) {
            $file->{tags} = $filetags;
            $meta->putKeyed( 'FILEATTACHMENT', $file );
            my @cache = ( $meta, $text, $web, $topic );
            $dirtyTopics->{"$web.$topic"} = \@cache;
            $report .= '%BR%%MAKETEXT{"Updated [_1] to \'[_2]\'" args="'." $web.$topic/$attachment,$filetags\"}%";
        }
    }

    # save changed topics
    $report .= '%MAKETEXT{"Nothing changed."}%' unless scalar keys %$dirtyTopics;
    foreach my $dirt ( keys %$dirtyTopics ) {
        my $cached = $dirtyTopics->{"$dirt"};
        my ( $meta, $text, $web, $topic ) = @$cached;
        try {
            Foswiki::Func::saveTopic( $web, $topic, $meta, $text, {minor => 1, dontlog => 1, ignorepermissions => 1} );
        } catch Error with {
            $report .= '%BR%%RED%%MAKETEXT{"Could not save [_1]" args="'."$web.$topic\"}%%ENDCOLOR%";
        }
    }

    my $display = Foswiki::Func::loadTemplate( 'BulkTagReport' );
    Foswiki::Func::setPreferencesValue( 'REPORT', $report );
    $display = Foswiki::Func::expandCommonVariables( $display );
    $display = Foswiki::Func::renderText( $display );
    return Foswiki::Func::expandCommonVariables( $display );
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
