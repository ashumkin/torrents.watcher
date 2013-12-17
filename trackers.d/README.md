Tracker descriptions folder
---------------------------
&lt;SOURCE&gt;./trackers.d/ folder contains tracker description files.
<br/>Each file must have '.tracker' extention to be autoloaded.

Tracker description file
------------------------
<br/>It is a Ruby code. It contains descriptive Hash.

```ruby
{
    :"trackername" => {
        # <trackername> is a shortname for tracker for reference by user config file
        # enabled
        :enabled => 1|true,
        :login => {
            # :check is optional URL to check whether we already logged in
            # (if not set :form is used)
            :check => <url_to_check_login>,
            # login form URL (used to login; also if :check is not set, used to check already logged in)
            :form => <url_to_login>,
            :fields => {
                # fields sent for logging in (to :form URL)
                # key is the name of field, value is it's value
                # if value is a symbol, it's value is taken from appropriate field
                # from user config file for this tracker (see README.userconfig.md)
                :username_field => :username_field_from_user_config,
                :password_field => :password_field_from_user_config,
                :any_other_field => 'any_other_field_value'
            },
            # :success_re is regexp. Its name is a little bit confusing.
            # It is a value that MUST NOT be contained in login page after successful login
            # Almost always after incorrect login tracker site outputs a page for next attempt to login
            # and contains a login form for this.
            # And, to the contrary, tracker site DOES NOT contain login form when we already logged in.
            # So, such "indicator of "we logged in" can be string like "<input name="username"..."
            :success_re = /regexp that MUST NOT be in login page after successful login/
        },
        # N.B. Some trackers have different methods of getting torrents but the same credentials for all of them
        # e.g. kinokopilka.tv has "topic", "bookmarks" and RSS feed (latter is glitchy but exists)
        # So, to avoid credentials duplication there is an ability to reference to credentials of another tracker
        [:login => :"other_tracker_name",]

        # :torrent section describes "rules" of getting a torrent file from its web-page
        :torrent => {
            # Optional :url is an URL to get torrent topic page
            # some trackers have "queue" page that has constant value
            # :url is for such trackers (e.g. kinokopilka.tv's bookmarks)
            :url => <URL>,

            # :replace_url. If true then ID for torrent file is taken from its topic URL,
            # matched by :match_re, and substituted by :replace regexp
            # See rutracker.org tracker description file, it has such a scheme:
            #   URL for torrent is http://rutracker.org/forum/viewtopic.php?t=<ID>
            #   URL for its torrent file is http://dl.rutracker.org/forum/dl.php?t=<ID>
            # So, to receive torrent file we just can take ID from topic URL
            # and substitute it to appropriate URL
            # but for more flexibility its implemented in RegExp's
            :replace_url => true

            # :match_re is a RegExp
            # when :replace_url is set to true, then it is RegExp to extract ID from torrent topic URL
            # otherwise page of a topic is scanned (line by line) for this RegExp
            :match_re => /regexp/

            # Optional :match_index is an integer or an array of TWO integers
            # which are backreferences for :match_re regexp.
            # Some trackers (e.g. kinokopilka.tv) have "queue" page that contains list of enqueued torrents.
            # With :match_re and :match_index we can extract that torrent links and its titles
            # (title is used for logging only)
            # If omitted default is 0, that is matched to whole match of :match_re (that is URL)
            :match_index => <index>|[<index_of_url>, <index_of_title>]

            # :replace is a RegExp used to substitute :match_re when :replace_url is set
            :replace => /regexp_to_get_torrent_file_url/

            # :post is a flag to use POST method for fetching torrent file
            # Some trackers (e.g. rutracker.org) use POST method for downloading torrent file but not GET
            # N.B. Please, do no use 0 as a FALSE, as far as Ruby's "0" gives TRUE in 'if 0' (see Ruby man)
            :post => true|false|nil
        }
    }
}
```

