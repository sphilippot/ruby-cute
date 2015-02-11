require 'restclient'
require 'yaml'
require 'json'
require 'ipaddress'
require 'uri'

module Cute
  module G5K

    # @api private
    class G5KArray < Array

      def uids
        return self.map { |it| it['uid'] }
      end

      def __repr__
        return self.map { |it| it.__repr__ }.to_s
      end

      def rel_self
        return rel('self')
      end

      def rel(r)
        return self['links'].detect { |x| x['rel'] == r }['href']
      end

    end

    # Provides an abstraction for handling G5K responses.
    # @api private
    # @see https://api.grid5000.fr/doc/3.0/reference/grid5000-media-types.html
    # When this structure is used to describe jobs, it is expected to have the
    # following fields which depend on the version of the API.
    #      {"uid"=>604692,
    #       "user_uid"=>"name",
    #       "user"=>"name",
    #       "walltime"=>3600,
    #       "queue"=>"default",
    #       "state"=>"running",
    #       "project"=>"default",
    #       "name"=>"rubyCute job",
    #       "types"=>["deploy"],
    #       "mode"=>"PASSIVE",
    #       "command"=>"./oarapi.subscript.ZzvnM",
    #       "submitted_at"=>1423575384,
    #       "scheduled_at"=>1423575386,
    #       "started_at"=>1423575386,
    #       "message"=>"FIFO scheduling OK",
    #       "properties"=>"(deploy = 'YES') AND maintenance = 'NO'",
    #       "directory"=>"/home/name",
    #       "events"=>[],
    #       "links"=>[{"rel"=>"self", "href"=>"/sid/sites/nancy/jobs/604692", "type"=>"application/vnd.grid5000.item+json"},
    #                 {"rel"=>"parent", "href"=>"/sid/sites/nancy", "type"=>"application/vnd.grid5000.item+json"}],
    #       "resources_by_type"=>
    #        {"cores"=>
    #           ["griffon-8.nancy.grid5000.fr",
    #            "griffon-8.nancy.grid5000.fr",
    #            "griffon-8.nancy.grid5000.fr",
    #            "griffon-8.nancy.grid5000.fr",
    #            "griffon-9.nancy.grid5000.fr",
    #            "griffon-9.nancy.grid5000.fr",
    #            "griffon-9.nancy.grid5000.fr",
    #            "griffon-9.nancy.grid5000.fr",
    #            "griffon-77.nancy.grid5000.fr",
    #            "griffon-77.nancy.grid5000.fr",
    #            "griffon-77.nancy.grid5000.fr",
    #            "griffon-77.nancy.grid5000.fr",
    #            "vlans"=>["5"]},
    #       "assigned_nodes"=>["griffon-8.nancy.grid5000.fr", "griffon-9.nancy.grid5000.fr", "griffon-77.nancy.grid5000.fr"],
    #       "deploy"=>
    #          {"created_at"=>1423575401,
    #           "environment"=>"http://public.sophia.grid5000.fr/~nniclausse/openmx.dsc",
    #           "key"=>"https://api.grid5000.fr/sid/sites/nancy/files/cruizsanabria-key-84f3f1dbb1279bc1bddcd618e26c960307d653c5",
    #           "nodes"=>["griffon-8.nancy.grid5000.fr", "griffon-9.nancy.grid5000.fr", "griffon-77.nancy.grid5000.fr"],
    #           "site_uid"=>"nancy",
    #           "status"=>"processing",
    #           "uid"=>"D-751096de-0c33-461a-9d27-56be1b2dd980",
    #           "updated_at"=>1423575401,
    #           "user_uid"=>"cruizsanabria",
    #           "vlan"=>5,
    #           "links"=>
    #              [{"rel"=>"self", "href"=>"/sid/sites/nancy/deployments/D-751096de-0c33-461a-9d27-56be1b2dd980", "type"=>"application/vnd.grid5000.item+json"},

    class G5KJSON < Hash

      def items
        return self['items']
      end

      def nodes
        return self['nodes']
      end

      def resources
        return self['resources_by_type']
      end

      def rel(r)
        return self['links'].detect { |x| x['rel'] == r }['href']
      end

      def uid
        return self['uid']
      end

      def rel_self
        return rel('self')
      end

      def rel_parent
        return rel('parent')
      end

      def __repr__
        return self['uid'] unless self['uid'].nil?
        return Hash[self.map { |k, v| [k, v.__repr__ ] }].to_s
      end

      def refresh(g5k)
        return g5k.get_json(rel_self)
      end

      def self.parse(s)
        return JSON.parse(s, :object_class => G5KJSON, :array_class => G5KArray)
      end

    end

    # Manages the low level operations for communicating with the REST API.
    # @api private
    class G5KRest

      attr_reader :user
      # Initializes a REST connection
      # @param uri [String] resource identifier which normally is the URL of the Rest API
      # @param user [String] user if authentication is needed
      # @param pass [String] password if authentication is needed
      def initialize(uri,api_version,user,pass)
        @user = user
        @pass = pass
        @api_version = api_version.nil? ? "sid" : api_version
        if (user.nil? or pass.nil?)
          @endpoint = uri # Inside Grid'5000
        else
          user_escaped = CGI.escape(user)
          pass_escaped = CGI.escape(pass)
          @endpoint = "https://#{user_escaped}:#{pass_escaped}@#{uri.split("https://")[1]}"
        end

        machine =`uname -ov`.chop
        @user_agent = "ruby-cute/#{VERSION} (#{machine}) Ruby #{RUBY_VERSION}"
        @api = RestClient::Resource.new(@endpoint, :timeout => 30)
        test_connection
      end

      # Returns a resource object
      # @param path [String] this complements the URI to address to a specific resource
      def resource(path)
        path = path[1..-1] if path.start_with?('/')
        return @api[path]
      end

      # @return [Hash] the HTTP response
      # @param path [String] this complements the URI to address to a specific resource
      def get_json(path)
        maxfails = 3
        fails = 0
        while true
          begin
            r = resource(path).get(:content_type => "application/json")
            return G5KJSON.parse(r)
          rescue RestClient::RequestTimeout
            fails += 1
            raise if fails > maxfails
            Kernel.sleep(1.0)
          end
        end
      end

      # Creates a resource on the server
      # @param path [String] this complements the URI to address to a specific resource
      # @param json [Hash] contains the characteristics of the resources to be created.
      def post_json(path, json)
        r = resource(path).post(json.to_json,
                                :content_type => "application/json",
                                :accept => "application/json",
                                :user_agent => @user_agent)
        return G5KJSON.parse(r)
      end

      # Deletes a resource on the server
      # @param path [String] this complements the URI to address to a specific resource
      def delete_json(path)
        begin
          return resource(path).delete()
        rescue RestClient::InternalServerError => e
          raise
        end
      end

      # @return the parent link
      def follow_parent(obj)
        get_json(obj.rel_parent)
      end

      private

      # Tests the connection and raises an error in case of a problem
      def test_connection
        begin
          return get_json("/#{@api_version}/")
        rescue RestClient::Unauthorized
          raise "Your Grid'5000 credentials are not recognized"
        end
      end

    end

    # This class helps you to access Grid'5000 REST API.
    # Thus, the most common actions such as reservation of nodes and deployment can be easily scripted.
    # To simplify the use of the module, it is better to create a file with the following information:
    #
    #     $ cat > ~/.grid5000_api.yml << EOF
    #     $ uri: https://api.grid5000.fr/
    #     $ username: user
    #     $ password: **********
    #     $ version: sid
    #     $ EOF
    #
    # The *username* and *password* are not necessary if you are using the module from inside Grid'5000.
    # You can take a look at the {Cute::G5K::API#initialize G5K::API constructor} to see more details for
    # this configuration.
    #
    # = Getting started
    #
    # As already said, the goal of {Cute::G5K::API G5K::API} class is to present a high level abstraction to manage the most common activities
    # in Grid'5000 such as: the reservation of resources and the deployment of environments.
    # Consequently, these activities can be easily scripted using Ruby.
    # The advantage of this is that you can use all Ruby constructs (e.g., loops, conditionals, blocks, iterators, etc) to script your experiments,
    # some methods proposed by {Cute::G5K::API G5K::API} raise exceptions that you can handle to decide the workflow of your experiment
    # (see {Cute::G5K::API#wait_for_deploy wait_for_deploy}).
    # Let's show how {Cute::G5K::API G5K::API} is used through an example, suppose we want to reserve 3 nodes in Nancy site for 1 hour.
    # In order to do that we would write something like this:
    #
    #     require 'cute'
    #
    #     g5k = Cute::G5K::API.new()
    #     job = g5k.reserve(:nodes => 3, :site => 'nancy', :walltime => '01:00:00')
    #
    # If that is all you want to do, you can write that into a file, let's say *example.rb* and execute it using the Ruby interpreter.
    #
    #     $ ruby example.rb
    #
    # The execution will block until you got the reservation. You can then interact with the nodes you reserved the way you used to or
    # add more code to the previous script for controlling your experiment with Ruby-Cute as shown in this {file:docs/g5k_exp_virt.md  example}.
    # We have just used the method {Cute::G5K::API#reserve reserve} that allow us to reserve resources in Grid'5000.
    # This method can be used to reserve resources in deployment mode and deploy our own software environment on them using
    # {http://kadeploy3.gforge.inria.fr/ Kadeploy}. For this we use the option *:env* of the {Cute::G5K::API#reserve reserve} method.
    # Therefore, it will first reserve the resources and then deploy the specified environment.
    # In this case {Cute::G5K::API#reserve reserve} will not block until the deployment is done, for that you have to execute
    # the method {Cute::G5K::API#wait_for_deploy wait_for_deploy}. The following Ruby script illustrates all we have just said.
    #
    #     require 'cute'
    #
    #     g5k = Cute::G5K::API.new()
    #
    #     job = g5k.reserve(:nodes => 1, :site => 'grenoble', :walltime => '00:40:00', :env => 'wheezy-x64-base')
    #
    #     g5k.wait_for_deploy(job)
    #
    # Your public ssh key located in ~/.ssh will be copied by default on the deployed machines,
    # you can specify another path for your keys with the option *:keys*.
    # In order to deploy your own environment, you have to put the tar file that contains the operating system you want to deploy and
    # the environment description file, under the public directory of a given site.
    # *VLANS* are supported by adding the parameter :vlan => type where type can be: *:routed*, *:local*, *:global*.
    # The following example, reserves 10 nodes in the Lille site, starts the deployment of a custom environment over the nodes
    # and puts the nodes under a local isolated VLAN.
    #
    #     require 'cute'
    #
    #     g5k = Cute::G5K::API.new()
    #
    #     job = g5k.reserve(:site => "lille", :nodes => 10,
    #                       :env => 'https://public.lyon.grid5000.fr/~user/debian_custom_img.yaml',
    #                       :vlan => :local, :keys => "~/my_ssh_key")
    #
    # If you do not want that the method {Cute::G5K::API#reserve reserve} perform the deployment for you, you have to use the option :type => :deploy.
    # This can be useful when deploying different environments in your reserved nodes. For example deploying the environments for a small HPC cluster.
    #
    #     require 'cute'
    #
    #     g5k = Cute::G5K::API.new()
    #
    #     job = g5k.reserve(:site => "lyon", :nodes => 5, :walltime => "03:00:00", :type => :deploy)
    #
    #     nodes = job["assigned_nodes"]
    #
    #     master = nodes[0]
    #     slaves = nodes[1..4]
    #
    #     g5k.deploy(job,:nodes => master, :env => 'https://public.lyon.grid5000.fr/~user/debian_master_img.yaml')
    #     g5k.deploy(job,:nodes => slaves, :env => 'https://public.lyon.grid5000.fr/~user/debian_slaves_img.yaml')
    #
    #     g5k.wait_for_deploy(job)
    #
    # You can check out the documentation of {Cute::G5K::API#reserve reserve} and {Cute::G5K::API#deploy deploy} methods
    # to know all the parameters supported and more complex uses.
    #
    # == Another useful methods
    #
    # Let's use *pry* to show other useful methods. As shown in {file:README.md Ruby Cute} the *cute* command will open a
    # pry shell with some modules preloaded and it will create the variable $g5k to access {Cute::G5K::API G5K::API} class.
    # Therefore, we can consult the name of the cluster available in a specific site.
    #
    #     [4] pry(main)> $g5k.cluster_uids("grenoble")
    #     => ["adonis", "edel", "genepi"]
    #
    # As well as the deployable environments:
    #
    #     [6] pry(main)> $g5k.environment_uids("grenoble")
    #     => ["squeeze-x64-base", "squeeze-x64-big", "squeeze-x64-nfs", "wheezy-x64-base", "wheezy-x64-big", "wheezy-x64-min", "wheezy-x64-nfs", "wheezy-x64-xen"]
    #
    # For getting a list of sites available in Grid'5000 you can use:
    #
    #     [7] pry(main)> $g5k.site_uids()
    #     => ["grenoble", "lille", "luxembourg", "lyon",...]
    #
    # We can get the status of nodes in a given site by using:
    #
    #     [8] pry(main)> $g5k.nodes_status("lyon")
    #      => {"taurus-2.lyon.grid5000.fr"=>"besteffort", "taurus-16.lyon.grid5000.fr"=>"besteffort", "taurus-15.lyon.grid5000.fr"=>"besteffort", ...}
    #
    # We can get information about our submitted jobs by using:
    #
    #    [11] pry(main)> $g5k.get_my_jobs("grenoble")
    #    => [{"uid"=>1679094,
    #         "user_uid"=>"cruizsanabria",
    #         "user"=>"cruizsanabria",
    #         "walltime"=>3600,
    #         "queue"=>"default",
    #         "state"=>"running", ...}, ...]
    #
    # If we are done with our experiment, we can release the submitted job or all jobs in a given site as follows:
    #
    #    [12] pry(main)> $g5k.release(job)
    #    [13] pry(main)> $g5k.release_all("grenoble")
    class API

      attr_accessor :logger
      # Initializes a REST connection for Grid'5000 API
      #
      # = Examples
      # You can specify another configuration file using the option :conf_file, for example:
      #
      #     g5k = Cute::G5K::API.new({:conf_file =>"config file path"})
      #
      # Or you can specify other parameter to use:
      #
      #     g5k = Cute::G5K::API.new({:uri => "https://api.grid5000.fr"})
      #
      # Other valid parameters are :username, :password, :version.
      # @param params [Hash] contains initialization parameters.
      def initialize(params={})
        config = {}
        default_file = "#{ENV['HOME']}/.grid5000_api.yml"

        if params[:conf_file].nil? then
          params[:conf_file] =  default_file if File.exist?(default_file)
        end

        config = YAML.load(File.open(params[:conf_file],'r')) unless params[:conf_file].nil?
        @user = params[:user] || config["username"]
        @pass = params[:pass] || config["password"]
        @uri = params[:uri] || config["uri"]
        @api_version = params[:version] || config["version"] || "sid"
        @logger = nil

        begin
          @g5k_connection = G5KRest.new(@uri,@api_version,@user,@pass)
        rescue
          msg_create_file = ""
          if (not File.exist?(default_file)) && params[:conf_file].nil? then
            msg_create_file = "Please create the file: ~/.grid5000_api.yml and
                          put the necessary credentials or use the option
                          :conf_file to indicate another file for the credentials"
          end
          raise "Unable to authorize against the Grid'5000 API.
               #{msg_create_file}"

        end
      end

      # It returns the site name. Example:
      #    site #=> "rennes"
      # This will only work when {Cute::G5K::API G5K::API} is used within Grid'5000.
      # In the other cases it will return *nil*
      # @return [String] the site name where the method is called on
      def site
        p = `hostname`.chop
        res = /^.*\.(.*).*\.grid5000.fr/.match(p)
        res[1] unless res.nil?
      end

      # @api private
      # @return the rest point for performing low level REST requests
      def rest
        @g5k_connection
      end

      # @return [String] Grid'5000 user
      def g5k_user
        return @user.nil? ? ENV['USER'] : @user
      end

      # Returns all sites identifiers
      #
      # = Example:
      #    site_uids #=> ["grenoble", "lille", "luxembourg", "lyon",...]
      #
      # @return [Array] all site identifiers
      def site_uids
        return sites.uids
      end

      # Returns all cluster identifiers
      #
      # = Example:
      #    cluster_uids("grenoble") #=> ["adonis", "edel", "genepi"]
      #
      # @return [Array] cluster identifiers
      def cluster_uids(site)
        return clusters(site).uids
      end

      # Returns the name of the environments deployable in a given site.
      # These can be used with {Cute::G5K::API#reserve reserve} and {Cute::G5K::API#deploy deploy} methods
      #
      # = Example:
      #    environment_uids("nancy") #=> ["squeeze-x64-base", "squeeze-x64-big", "squeeze-x64-nfs", ...]
      #
      # @return [Array] environment identifiers
      def environment_uids(site)
        # environments are returned by the API following the format squeeze-x64-big-1.8
        # it returns environments without the version
        return environments(site).uids.map{ |e| /(.*)-(.*)/.match(e)[1]}.uniq
      end

      # @return [Hash] all the status information of a given Grid'5000 site
      # @param site [String] a valid Grid'5000 site name
      def site_status(site)
        @g5k_connection.get_json(api_uri("sites/#{site}/status"))
      end

      # @return [Hash] the nodes state (e.g, free, busy, etc) that belong to a given Grid'5000 site
      # @param site [String] a valid Grid'5000 site name
      def nodes_status(site)
        nodes = {}
        site_status(site).nodes.each do |node|
          name = node[0]
          status = node[1]["soft"]
          nodes[name] = status
        end
        return nodes
      end

      # @return [Array] the description of all Grid'5000 sites
      def sites
        @g5k_connection.get_json(api_uri("sites")).items
      end

      # @return [Array] the description of clusters that belong to a given Grid'5000 site
      # @param site [String] a valid Grid'5000 site name
      def clusters(site)
        @g5k_connection.get_json(api_uri("sites/#{site}/clusters")).items
      end

      # @return [Array] the description of all environments registered in a Grid'5000 site
      def environments(site)
        @g5k_connection.get_json(api_uri("sites/#{site}/environments")).items
      end

      # @return [Hash] all the jobs submitted in a given Grid'5000 site,
      #         if a uid is provided only the jobs owned by the user are shown.
      # @param site [String] a valid Grid'5000 site name
      # @param uid [String] user name in Grid'5000
      # @param state [String] jobs state: running, waiting
      def get_jobs(site, uid = nil, state = nil)
        filter = "?"
        filter += state.nil? ? "" : "state=#{state}"
        filter += uid.nil? ? "" : "&user=#{uid}"
        filter += "limit=25" if (state.nil? and uid.nil?)
        jobs = @g5k_connection.get_json(api_uri("/sites/#{site}/jobs/#{filter}")).items
        jobs.map{ |j| @g5k_connection.get_json(j.rel_self)}
        # This request sometime is could take a little long when all jobs are requested
        # The API return by default 50 the limit was set to 25 (e.g., 23 seconds).
      end

      # @return [Hash] the last 50 deployments performed in a Grid'5000 site
      # @param site [String] a valid Grid'5000 site name
      # @param uid [String] user name in Grid'5000
      def get_deployments(site, uid = nil)
        @g5k_connection.get_json(api_uri("sites/#{site}/deployments/?user=#{uid}")).items
      end

      # @return [Hash] information concerning a given job submitted in a Grid'5000 site
      # @param site [String] a valid Grid'5000 site name
      # @param jid [Fixnum] a valid job identifier
      def get_job(site, jid)
        @g5k_connection.get_json(api_uri("/sites/#{site}/jobs/#{jid}"))
      end

      # @return [Hash] switches information available in a given Grid'5000 site.
      # @param site [String] a valid Grid'5000 site name
      def get_switches(site)
        items = @g5k_connection.get_json(api_uri("/sites/#{site}/network_equipments")).items
        items = items.select { |x| x['kind'] == 'switch' }
        # extract nodes connected to those switches
        items.each { |switch|
          conns = switch['linecards'].detect { |c| c['kind'] == 'node' }
          next if conns.nil?  # IB switches for example
          nodes = conns['ports'] \
            .select { |x| x != {} } \
            .map { |x| x['uid'] } \
            .map { |x| "#{x}.#{site}.grid5000.fr"}
          switch['nodes'] = nodes
        }
        return items.select { |it| it.key?('nodes') }
      end

      # @return [Hash] information of a specific switch available in a given Grid'5000 site.
      # @param site [String] a valid Grid'5000 site name
      # @param name [String] a valid switch name
      def get_switch(site, name)
        s = get_switches(site).detect { |x| x.uid == name }
        raise "Unknown switch '#{name}'" if s.nil?
        return s
      end

      # Returns information of all my jobs submitted in a given site.
      # By default it only shows the jobs in state *running*.
      # You can specify another state like this:
      #
      # = Example
      #    get_my_jobs("nancy", state="waiting")
      # Valid states are specified in {https://api.grid5000.fr/doc/4.0/reference/spec.html Grid'5000 API spec}
      # @return [Array] all my submitted jobs to a given site and their associated deployments.
      # @param site [String] a valid Grid'5000 site name
      def get_my_jobs(site, state="running")
        jobs = get_jobs(site, g5k_user,state)
        deployments = get_deployments(site, g5k_user)
        # filtering deployments
        jobs.map{ |j| j["deploy"] = deployments.select{ |d| d["created_at"] > j["started_at"]} }
        return jobs
      end

      # Returns an Array with all subnets reserved by a given job.
      # Each element of the Array is a {https://github.com/bluemonk/ipaddress IPAddress::IPv4} object which we can interact with to obtain
      # the details of our reserved subnets:
      #
      # = Example
      #  require 'cute'
      #
      #    g5k = Cute::G5K::API.new()
      #
      #    job = g5k.reserve(:site => "lyon", :resources => "/slash_22=1+{virtual!='none'}/nodes=1")
      #
      #    subnet = g5k.get_subnets(job).first #=> we use 'first' because it is an array and we only reserved one subnet.
      #
      #    ips = subnet.map{ |ip| ip.to_s }
      #
      # @return [Array] all the subnets defined in a given job
      # @param job [G5KJSON] as described in {Cute::G5K::G5KJSON job}
      def get_subnets(job)
        subnets = job.resources["subnets"]
        subnets.map{|s| IPAddress::IPv4.new s }
      end

      # @return [Array] all the nodes in the VLAN
      # @param job [G5KJSON] as described in {Cute::G5K::G5KJSON job}
      def get_vlan_nodes(job)
        if job["deploy"].nil?
          return nil
        else
          vlan_id = job["deploy"].is_a?(Array)? job["deploy"].first["vlan"] : job["deploy"]["vlan"]
        end
        nodes = job["assigned_nodes"]
        reg = /^(\w+-\d+)(\..*)$/
        nodes.map {|name| reg.match(name)[1]+"-kavlan-"+vlan_id.to_s+reg.match(name)[2]}
      end

      # Releases all jobs on a site
      # @param site [String] a valid Grid'5000 site name
      def release_all(site)
        Timeout.timeout(20) do
          jobs = get_my_jobs(site)
          break if jobs.empty?
          begin
            jobs.each { |j| release(j) }
          rescue RestClient::InternalServerError => e
            raise unless e.response.include?('already killed')
          end
        end
      end

      # Releases a resource, it can be a job or a deploy.
      def release(r)
        begin
          return @g5k_connection.delete_json(r.rel_self)
        rescue RestClient::InternalServerError => e
          raise unless e.response.include?('already killed')
        end
      end

      # Helper for making the reservations the easy way. These are the supported parameters:
      #
      #     reserve(:nodes => 1, # number of nodes to reserve
      #             :walltime => '01:00:00', # walltime of the reservation
      #             :site => "nancy", # Grid'5000 site
      #             :type => :deploy, # type of reservation: :deploy, :allow_classic_ssh
      #             :name => "my reservation", # name to be assigned to the reservation
      #             :cluster=> "graphene", # name of the cluster
      #             :subnets => [prefix_size, 2], # subnet reservation
      #             :env => "wheezy-x64-big", # environment name for kadeploy
      #             :vlan => :routed, # VLAN type
      #             :properties => "wattmeter='YES'", #
      #             :resources => "{cluster='graphene'}/nodes=2+{cluster='griffon'}/nodes=3" # OAR syntax for complex submissions.
      #             )
      #
      # = Examples of reservations with properties:
      #
      #     job = g5k.reserve(:site => 'lyon', :nodes => 2, :properties => "wattmeter='YES'")
      #
      #     job = g5k.reserve(:site => 'nancy', :nodes => 1, :properties => "switch='sgraphene1'")
      #
      #     job = g5k.reserve(:site => 'nancy', :nodes => 1, :properties => "cputype='Intel Xeon E5-2650'")
      #
      # = Subnet reservation and network isolation
      #
      # The example below reserves 2 nodes in the cluster *chirloute* located in Lille for 1 hour as well as 2 /22 subnets.
      # We will get 2048 IP addresses that can be used, for example, in virtual machines.
      #
      #     job = g5k.reserve(:site => 'lille', :cluster => 'chirloute', :nodes => 2,
      #                            :time => '01:00:00', :env => 'wheezy-x64-xen',
      #                            :keys => "~/my_ssh_jobkey",
      #                            :subnets => [22,2])
      #
      # If walltime is not specified, 1 hour walltime will be assigned to the reservation.
      #
      # = Reserving with OAR hierarchy
      #
      # All non-deploy reservations are submitted by default with the OAR option "-allow_classic_ssh"
      # which does not take advantage of the CPU/core management level.
      # Therefore, in order to take advantage of this capability, SSH keys have to be specified at the moment of reserving resources.
      # This has to be used whenever we perform a reservation with cpu and core hierarchy.
      # Users are encouraged to create a pair of SSH keys for managing jobs, for instance the following command can be used:
      #
      #     ssh-keygen -N "" -t rsa -f ~/my_ssh_jobkey
      #
      # The reserved nodes can be accessed using "oarsh" or by configuring the SSH connection as shown in {https://www.grid5000.fr/mediawiki/index.php/OAR2 OAR2}.
      # You have to specify different keys per reservation if you want several jobs running at the same time in the same site.
      # Examples using the OAR hierarchy:
      #
      #     job = g5k.reserve(:site => "grenoble", :switches => 3, :nodes => 1, :cpus => 1, :cores => 1, :keys => "~/my_ssh_jobkey")
      #
      # The previous reservation can be done as well using the OAR syntax:
      #
      #     job = g5k.reserve(:site => "grenoble", :resources => "/switch=3/nodes=1/cpu=1/core=1", :keys => "~/my_ssh_jobkey")
      #
      # The parameter :resources can replace :site, : walltime, :cluster, etc, which are shortcuts for OAR syntax.
      # This syntax allow to express more complex reservations. For example, combining OAR hierarchy with properties:
      #
      #     job = g5k.reserve(:site => "grenoble", :resources => "{ib10g='YES' and memnode=24160}/cluster=1/nodes=2/core=1", :keys => "~/my_ssh_jobkey")
      #
      # If we want 2 nodes with the following constraints:
      # 1) nodes on 2 different clusters of the same site, 2) nodes with virtualization capability enabled
      # 3) 1 /22 subnet. The reservation will be like:
      #
      #     job = g5k.reserve(:site => "rennes", :resources => "/slash_22=1+{virtual!='none'}/cluster=2/nodes=1")
      #
      # Another reservation for two clusters:
      #
      #     job = g5k.reserve(:site => "nancy", :resources => "{cluster='graphene'}/nodes=2+{cluster='griffon'}/nodes=3")
      #
      # reservation using a local VLAN
      #
      #     job = g5k.reserve(:site => 'nancy', :resources => "{type='kavlan-local'}/vlan=1,nodes=1", :env => 'wheezy-x64-xen')
      #
      # @return [G5KJSON] as described in {Cute::G5K::G5KJSON job}
      # @param opts [Hash] options compatible with OAR
      def reserve(opts)

        nodes = opts.fetch(:nodes, 1)
        walltime = opts.fetch(:walltime, '01:00:00')
        at = opts[:at]
        site = opts[:site]
        type = opts[:type]
        name = opts.fetch(:name, 'rubyCute job')
        command = opts[:cmd]
        async = opts[:async]
        ignore_dead = opts[:ignore_dead]
        cluster = opts[:cluster]
        switches = opts[:switches]
        cpus = opts[:cpus]
        cores = opts[:cores]
        subnets = opts[:subnets]
        properties = opts[:properties]
        resources = opts.fetch(:resources, "")
        type = :deploy if opts[:env]
        keys = opts[:keys]

        vlan_opts = {:routed => "kavlan",:global => "kavlan-global",:local => "kavlan-local"}
        vlan = nil
        unless opts[:vlan].nil?
          if vlan_opts.include?(opts[:vlan]) then
            vlan = vlan_opts.fetch(opts[:vlan])
          else
            raise 'Option for vlan not recognized'
          end
        end

        raise 'At least nodes, time and site must be given'  if [nodes, walltime, site].any? { |x| x.nil? }

        secs = walltime.to_secs
        walltime = walltime.to_time

        if nodes.is_a?(Array)
          all_nodes = nodes
          nodes = filter_dead_nodes(nodes) if ignore_dead
          removed_nodes = all_nodes - nodes
          info "Ignored nodes #{removed_nodes}." unless removed_nodes.empty?
          hosts = nodes.map { |n| "'#{n}'" }.sort.join(',')
          properties = "host in (#{hosts})"
          nodes = nodes.length
        end

        raise 'Nodes must be an integer.' unless nodes.is_a?(Integer)

        command = "sleep #{secs}" if command.nil?
        type = type.to_sym unless type.nil?

        if resources == ""
          resources = "/switch=#{switches}" unless switches.nil?
          resources += "/nodes=#{nodes}"
          resources += "/cpu=#{cpus}" unless cpus.nil?
          resources += "/core=#{cores}" unless cores.nil?
          resources = "{cluster='#{cluster}'}" + resources unless cluster.nil?
          resources = "{type='#{vlan}'}/vlan=1+" + resources unless vlan.nil?
          resources = "slash_#{subnets[0]}=#{subnets[1]}+" + resources unless subnets.nil?
        end

        resources += ",walltime=#{walltime}" unless resources.include?("walltime")

        payload = {
                   'resources' => resources,
                   'name' => name,
                   'command' => command
                  }

        info "Reserving resources: #{resources} (type: #{type}) (in #{site})"

        payload['properties'] = properties unless properties.nil?


        payload['types'] = [ type.to_s ] unless type.nil?

        if not type == :deploy
          if opts[:keys]
            payload['import-job-key-from-file'] = [ File.expand_path(keys) ]
          else
            payload['types'] = [ 'allow_classic_ssh' ]
          end
        end

        unless at.nil?
          dt = parse_time(at)
          payload['reservation'] = dt
          info "Starting this reservation at #{dt}"
        end

        begin
          # Support for the option "import-job-key-from-file"
          # The request has to be redirected to the OAR API given that Grid'5000 API
          # does not support some OAR options.
          if payload['import-job-key-from-file'] then
            # Adding double quotes otherwise we have a syntax error from OAR API
            payload["resources"] = "\"#{payload["resources"]}\""
            temp = @g5k_connection.post_json(api_uri("sites/#{site}/internal/oarapi/jobs"),payload)
            sleep 1 # This is for being sure that our job appears on the list
            r = get_my_jobs(site,nil).select{ |j| j["uid"] == temp["id"] }.first
          else
            r = @g5k_connection.post_json(api_uri("sites/#{site}/jobs"),payload)  # This makes reference to the same class
          end
        rescue => e
          info "Fail posting the json to the API"
          info e.message
          info e.http_body
          raise
        end

        job = @g5k_connection.get_json(r.rel_self)
        job = wait_for_job(job) if async != true
        opts.delete(:nodes) # to not collapse with deploy options
        deploy(job,opts) unless opts[:env].nil? #type == :deploy
        return job

      end

      # waits for a job to be in a running state
      # @param job [String] valid job identifier
      # @param wait_time [Fixnum] wait time before raising an exception, default 10h
      def wait_for_job(job,wait_time = 36000)

        jid = job
        info "Waiting for reservation #{jid}"
        Timeout.timeout(wait_time) do
          while true
            job = job.refresh(@g5k_connection)
            t = job['scheduled_at']
            if !t.nil?
              t = Time.at(t)
              secs = [ t - Time.now, 0 ].max.to_i
              info "Reservation #{jid} should be available at #{t} (#{secs} s)"
            end
            break if job['state'] == 'running'
            raise "Job is finishing." if job['state'] == 'finishing'
            Kernel.sleep(5)
          end
        end
        info "Reservation #{jid} ready"
        return job
      end

      # Deploy an environment in a set of reserved nodes using {http://kadeploy3.gforge.inria.fr/ Kadeploy}.
      # A job structure returned by {Cute::G5K::API#reserve reserve} or {Cute::G5K::API#get_my_jobs get_my_jobs} methods
      # is mandatory as a parameter as well as the environment to deploy.
      #
      # = Examples
      # Deploying the production environment *wheezy-x64-base* on all the reserved nodes:
      #
      #    deploy(job, :env => "wheezy-x64-base")
      #
      # Other parameters you can specify are :nodes [Array] for deploying on specific nodes within a job and
      # :keys [String] to specify the public key to use during the deployment.
      #
      #    deploy(job, :nodes => ["genepi-2.grid5000.fr"], :env => "wheezy-x64-xen", :keys => "~/my_key.pub")
      #
      # @param job [G5KJSON] as described in {Cute::G5K::G5KJSON job}
      # @param opts [Hash] options structure
      # @return [G5KJSON] a job with deploy information as described in {Cute::G5K::G5KJSON job}
      def deploy(job, opts = {})

        nodes = opts[:nodes].nil? ? job['assigned_nodes'] : opts[:nodes]

        raise "Unrecognized nodes format" unless nodes.is_a?(Array)

        env = opts[:env]


        site = @g5k_connection.follow_parent(job).uid

        if opts[:keys].nil? then
          public_key_path = File.expand_path("~/.ssh/id_rsa.pub")
          public_key_file = File.exist?(public_key_path) ? File.read(public_key_path) : ""
        else
          public_key_file = File.read("#{File.expand_path(opts[:keys])}.pub")
        end

        raise "Environment must be given" if env.nil?

        payload = {
                   'nodes' => nodes,
                   'environment' => env,
                   'key' => public_key_file,
                  }

        if !job.resources["vlans"].nil?
          vlan = job.resources["vlans"].first
          payload['vlan'] = vlan
          info "Found VLAN with uid = #{vlan}"
        end

        info "Creating deployment"

        begin
          r = @g5k_connection.post_json(api_uri("sites/#{site}/deployments"), payload)
        rescue => e
          raise e
        end
        job["deploy"] = [] if job["deploy"].nil?

        job["deploy"].push(r)

        return job

      end

      # Returns the status of all deployments performed within a job.
      # The results can be filtered using a Hash with valid deployment properties
      # described in {https://api.grid5000.fr/doc/4.0/reference/spec.html Grid'5000 API spec}.
      #
      # = Example
      #
      #   deploy_status(job, :nodes => ["adonis-10.grenoble.grid5000.fr"], :status => "terminated")
      #
      # @return [Array] status of deploys within a job
      # @param job [G5KJSON] as described in {Cute::G5K::G5KJSON job}
      # @param filter [Hash] filter the deployments to be returned.
      def deploy_status(job,filter = {})

        job["deploy"].map!{  |d| d.refresh(@g5k_connection) }

        filter.keep_if{ |k,v| v} # removes nil values
        if filter.empty?
          status = job["deploy"].map{ |d| d["status"] }
        else
          status = job["deploy"].map{ |d| d["status"] if filter.select{ |k,v| d[k.to_s] != v }.empty? }
        end
        return status.compact

      end

      # Blocks until deployments have *terminated* status
      #
      # = Examples
      # This method requires a job as a parameter and it will blocks by default until all deployments
      # within the job pass form *processing* status to *terminated* status.
      #
      #    wait_for_deploy(job)
      #
      # You can wait for specific deployments using the option :nodes. This can be useful when performing different deployments on the reserved resources.
      #
      #    wait_for_deploy(job, :nodes => ["adonis-10.grenoble.grid5000.fr"])
      #
      # Another parameter you can specify is :wait_time that allows you to timeout the deployment (by default is 10h). The method will throw a Timeout::Error exception
      # that you can catch and react upon. This example illustrates how this can be used.
      #
      #    require 'cute'
      #
      #    g5k = Cute::G5K::API.new()
      #
      #    job = g5k.reserve(:nodes => 1, :site => 'lyon', :env => 'wheezy-x64-base')
      #
      #    begin
      #      g5k.wait_for_deploy(job,:wait_time => 100)
      #      rescue  Timeout::Error
      #      puts "We waited too long let's release the job"
      #      g5k.release(job)
      #    end
      #
      # @param job [G5KJSON] as described in {Cute::G5K::G5KJSON job}
      # @param opts [Hash] options
      def wait_for_deploy(job,opts = {})
        opts.merge!({:wait_time => 36000}) if opts[:wait_time].nil?
        nodes = opts[:nodes]
#        did = job["deploy"].is_a?(Array)? job["deploy"].first : job["deploy"]
        Timeout.timeout(opts[:wait_time]) do
          # it will ask just for processing status
          status = deploy_status(job,{:nodes => nodes, :status => "processing"})
          until status.empty? do
            info "Waiting for #{status.length} deployment"
            sleep 4
            status = deploy_status(job,{:nodes => nodes, :status => "processing"})
          end
          info "Deployment finished"
          return status
        end
      end

      private
      # Handles the output of messages within the module
      # @param msg [String] message to show
      def info(msg)
        if @logger.nil? then
          t = Time.now
          s = t.strftime('%Y-%m-%d %H:%M:%S.%L')
          puts "#{s} => #{msg}"
        else
          @logger.info(msg)
        end
      end

      # @return a valid Grid'5000 resource
      # it avoids "//"
      def api_uri(path)
        path = path[1..-1] if path.start_with?('/')
        return "#{@api_version}/#{path}"
      end

    end

  end
end
