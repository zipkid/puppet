require 'etc'
require 'facter'
require 'puppet/type/property'

module Puppet
    newtype(:user) do
        @doc = "Manage users.  This type is mostly built to manage system
            users, so it is lacking some features useful for managing normal
            users.
            
            This element type uses the prescribed native tools for creating
            groups and generally uses POSIX APIs for retrieving information
            about them.  It does not directly modify /etc/passwd or anything.
            
            For most platforms, the tools used are ``useradd`` and its ilk;
            for Mac OS X, NetInfo is used.  This is currently unconfigurable,
            but if you desperately need it to be so, please contact us."

        feature :allows_duplicates,
            "The provider supports duplicate users with the same UID."

        feature :manages_homedir,
            "The provider can create and remove home directories."

#        feature :manages_passwords,
#            "The provider can modify user passwords, by accepting a password
#            hash."

        newproperty(:ensure) do
            newvalue(:present, :event => :user_created) do
                provider.create
            end

            newvalue(:absent, :event => :user_removed) do
                provider.delete
            end

            desc "The basic state that the object should be in."

            # If they're talking about the thing at all, they generally want to
            # say it should exist.
            defaultto do
                if @parent.managed?
                    :present
                else
                    nil
                end
            end

            def change_to_s
                begin
                    if @is == :absent
                        return "created"
                    elsif self.should == :absent
                        return "removed"
                    else
                        return "%s changed '%s' to '%s'" %
                            [self.name, self.is_to_s, self.should_to_s]
                    end
                rescue Puppet::Error, Puppet::DevError
                    raise
                rescue => detail
                    raise Puppet::DevError,
                        "Could not convert change %s to string: %s" %
                        [self.name, detail]
                end
            end

            def retrieve
                if provider.exists?
                    @is = :present
                else
                    @is = :absent
                end
            end

            # The default 'sync' method only selects among a list of registered
            # values.
            def sync
                if self.insync?
                    self.info "already in sync"
                    return nil
                #else
                    #self.info "%s vs %s" % [self.is.inspect, self.should.inspect]
                end
                unless self.class.values
                    self.devfail "No values defined for %s" %
                        self.class.name
                end

                # Set ourselves to whatever our should value is.
                self.set(self.should)
            end

        end

        newproperty(:uid) do
            desc "The user ID.  Must be specified numerically.  For new users
                being created, if no user ID is specified then one will be
                chosen automatically, which will likely result in the same user
                having different IDs on different systems, which is not
                recommended.  This is especially noteworthy if you use Puppet
                to manage the same user on both Darwin and other platforms,
                since Puppet does the ID generation for you on Darwin, but the
                tools do so on other platforms."

            munge do |value|
                case value
                when String
                    if value =~ /^[-0-9]+$/
                        value = Integer(value)
                    end
                end

                return value
            end
        end

        newproperty(:gid) do
            desc "The user's primary group.  Can be specified numerically or
                by name."
            
            def found?
                defined? @found and @found
            end

            munge do |gid|
                method = :getgrgid
                case gid
                when String
                    if gid =~ /^[-0-9]+$/
                        gid = Integer(gid)
                    else
                        method = :getgrnam
                    end
                when Symbol
                    unless gid == :auto or gid == :absent
                        self.devfail "Invalid GID %s" % gid
                    end
                    # these are treated specially by sync()
                    return gid
                end

                if group = Puppet::Util.gid(gid)
                    @found = true
                    return group
                else
                    @found = false
                    return gid
                end
            end

            # *shudder*  Make sure that we've looked up the group and gotten
            # an ID for it.  Yuck-o.
            def should
                unless defined? @should
                    return super
                end
                unless found?
                    @should = @should.each { |val|
                        next unless val
                        Puppet::Util.gid(val)
                    }
                end
                super
            end
        end

        newproperty(:comment) do
            desc "A description of the user.  Generally is a user's full name."
        end

        newproperty(:home) do
            desc "The home directory of the user.  The directory must be created
                separately and is not currently checked for existence."
        end

        newproperty(:shell) do
            desc "The user's login shell.  The shell must exist and be
                executable."
        end

#        newproperty(:password) do
#            desc "The user's password, in whatever format the local machine requires
#                (usually crypt)."
#
#            validate do |val|
#                unless val.to_s == "absent"
#                    unless provider.class.feature?(:manages_passwords)
#                        raise ArgumentError,
#                            "The %s provider can not manage passwords on %s" %
#                            [provider.class.name, Facter.value(:operatingsystem)]
#                    end
#                end
#            end
#        end

        newproperty(:groups) do
            desc "The groups of which the user is a member.  The primary
                group should not be listed.  Multiple groups should be
                specified as an array."

            def should_to_s
                self.should
            end

            def is_to_s
                @is.join(",")
            end

            # We need to override this because the groups need to
            # be joined with commas
            def should
                unless defined? @is
                    retrieve
                end

                unless defined? @should and @should
                    return nil
                end

                if @parent[:membership] == :inclusive
                    return @should.sort.join(",")
                else
                    members = @should
                    if @is.is_a?(Array)
                        members += @is
                    end
                    return members.uniq.sort.join(",")
                end
            end

            def retrieve
                if tmp = provider.groups
                    @is = tmp.split(",")
                else
                    @is = :absent
                end
            end

            def insync?
                unless defined? @should and @should
                    return true
                end
                unless defined? @is and @is
                    return true
                end
                tmp = @is
                if @is.is_a? Array
                    tmp = @is.sort.join(",")
                end

                return tmp == self.should
            end

            validate do |value|
                if value =~ /^\d+$/
                    raise ArgumentError, "Group names must be provided, not numbers"
                end
            end
        end

        # these three properties are all implemented differently on each platform,
        # so i'm disabling them for now

        # FIXME Puppet::Property::UserLocked is currently non-functional
        #newproperty(:locked) do
        #    desc "The expected return code.  An error will be returned if the
        #        executed command returns something else."
        #end

        # FIXME Puppet::Property::UserExpire is currently non-functional
        #newproperty(:expire) do
        #    desc "The expected return code.  An error will be returned if the
        #        executed command returns something else."
        #    @objectaddflag = "-e"
        #end

        # FIXME Puppet::Property::UserInactive is currently non-functional
        #newproperty(:inactive) do
        #    desc "The expected return code.  An error will be returned if the
        #        executed command returns something else."
        #    @objectaddflag = "-f"
        #end

        newparam(:name) do
            desc "User name.  While limitations are determined for
                each operating system, it is generally a good idea to keep to
                the degenerate 8 characters, beginning with a letter."
            isnamevar
        end

        newparam(:membership) do
            desc "Whether specified groups should be treated as the only groups
                of which the user is a member or whether they should merely
                be treated as the minimum membership list."
                
            newvalues(:inclusive, :minimum)

            defaultto :minimum
        end

        newparam(:allowdupe, :boolean => true) do
            desc "Whether to allow duplicate UIDs."
                
            newvalues(:true, :false)

            defaultto false
        end

        newparam(:managehome, :boolean => true) do
            desc "Whether to manage the home directory when managing the user."

            newvalues(:true, :false)

            defaultto false

            validate do |val|
                if val.to_s == "true"
                    unless provider.class.manages_homedir?
                        raise ArgumentError, "User provider %s can not manage home directories" % provider.class.name
                    end
                end
            end
        end

        # Autorequire the group, if it's around
        autorequire(:group) do
            autos = []

            if obj = @parameters[:gid] and groups = obj.shouldorig
                groups = groups.collect { |group|
                    if group =~ /^\d+$/
                        Integer(group)
                    else
                        group
                    end
                }
                groups.each { |group|
                    case group
                    when Integer:
                        if obj = Puppet.type(:group).find { |gobj|
                            gobj.should(:gid) == group
                        }
                            autos << obj
                            
                        end
                    else
                        autos << group
                    end
                }
            end

            if obj = @parameters[:groups] and groups = obj.should
                autos += groups.split(",")
            end

            autos
        end

        def self.list_by_name
            users = []
            defaultprovider.listbyname do |user|
                users << user
            end
            return users
        end

        def self.list
            defaultprovider.list

            self.collect do |user|
                user
            end
        end

        def retrieve
            absent = false
            properties().each { |property|
                if absent
                    property.is = :absent
                else
                    property.retrieve
                end

                if property.name == :ensure and property.is == :absent
                    absent = true
                    next
                end
            }
        end
    end
end

# $Id$
