# frozen_string_literal: true

class Workflow
  include ActiveModel::Model
  include ProjectPermissions

  class << self
    def workflow_dir(project_dir)
      Pathname.new("#{project_dir}/.ondemand/workflows")
    end

    def find(id, project_dir)
      file = "#{workflow_dir(project_dir)}/#{id}.yml"
      Workflow.from_yaml(file)
    end

    def all(project_dir)
      Dir.glob("#{workflow_dir(project_dir)}/*.yml").map do |file|
        Workflow.from_yaml(file)
      end.compact.sort_by { |s| s.created_at }
    end

    def from_yaml(file)
      contents = File.read(file)
      opts = YAML.safe_load(contents).deep_symbolize_keys
      new(opts)
    rescue StandardError, Errno::ENOENT => e
      Rails.logger.warn("Did not find workflow due to error #{e}")
      nil
    end

    def next_id
      SecureRandom.alphanumeric(8).downcase
    end

    def build_submit_params(metadata, project_dir)
      meta = metadata[:metadata] || {}
      {
        launcher_ids: meta[:boxes].map { |b| b["id"] },
        source_ids: meta[:edges].map { |e| e["from"] },
        target_ids: meta[:edges].map { |e| e["to"] },
        edges: meta[:edges] || [],
        project_dir: project_dir,
        start_launcher: meta[:start_launcher] || nil
      }
    end
  end

  attr_accessor :id, :name, :description, :project_dir, :created_at, :launcher_ids, :metadata

  validates :name, presence: true
  validates :launcher_ids, length: {minimum: 1}

  def initialize(attributes = {})
    @id = attributes[:id]
    @name = attributes[:name]
    @description = attributes[:description]
    @project_dir = attributes[:project_dir].to_s
    @created_at = attributes[:created_at]
    @launcher_ids = attributes[:launcher_ids] || []
    @metadata = attributes[:metadata] || {}
  end

  def to_h
    {
      :id => id,
      :name => name,
      :description => description,
      :created_at => created_at,
      :project_dir => project_dir,
      :launcher_ids => launcher_ids,
      :metadata => metadata
    }
  end

  def save
    return false unless valid?(:create)

    if @project_dir.empty?
      errors.add(:save, "I18n.t('dashboard.jobs_project_directory_error')")
      return false
    end

    @created_at = Time.now.to_i if @created_at.nil?
    @id = Workflow.next_id if id.blank?
    save_manifest(:save)
  end

  def save_manifest(operation)
    FileUtils.touch(manifest_file) unless manifest_file.exist?
    if editable?
      Pathname(manifest_file).write(to_h.as_json.compact.to_yaml)
    end

    true
  rescue StandardError => e
    errors.add(operation, I18n.t('dashboard.jobs_project_save_error', path: manifest_file))
    Rails.logger.warn "Cannot save workflow manifest: #{manifest_file} with error #{e.class}:#{e.message}"
    false
  end

  def collect_errors
    errors.map(&:message).join(', ')
  end

  def destroy!
    FileUtils.remove_entry(manifest_file, true)
    true
  end

  def manifest_file
    Workflow.workflow_dir(@project_dir).join("#{@id}.yml")
  end

  def update(attributes, override = false)
    update_attrs(attributes, override)
    return false unless valid?(:update)

    save_manifest(:update)
  end

  def update_attrs(attributes, override = false)
    [:name, :description, :launcher_ids, :metadata].each do |attribute|
      next unless override || attributes.key?(attribute)
      instance_variable_set("@#{attribute}".to_sym, attributes.fetch(attribute, ''))
    end
  end

  def editable?
    manifest_file.writable? || !shared?(manifest_file)
  end

  def submit(attributes = {})
    graph = Dag.new(attributes)
    if graph.has_cycle
      errors.add("Submit", "Specified edges form a cycle not directed-acyclic graph")
      return nil
    end
    dependency = graph.dependency
    order = graph.order
    Rails.logger.info("Dependency list created by DAG #{dependency}")
    Rails.logger.info("Order in which launcher got submitted #{order}")

    all_launchers = Launcher.all(attributes[:project_dir])
    job_id_hash = {}  # launcher-job_id hash
    port_connections = build_port_connections(attributes[:edges] || [], all_launchers)
    Rails.logger.info("Port connections: #{port_connections}")

    for id in order
      launcher = all_launchers.find { |l| l.id == id }
      unless launcher
        Rails.logger.warn("No launcher found for id #{id}, skipping...")
        next
      end
      dependent_launchers = dependency[id] || []

      begin
        jobs = dependent_launchers.map { |dep_id| job_id_hash.dig(dep_id, :job_id) }.compact
        port_overrides = port_connections[id] || {}
        opts = submit_launcher_params(launcher, jobs, port_overrides).to_h.symbolize_keys
        job_id = launcher.submit(opts, write_cache: false)
        if job_id.nil?
          Rails.logger.warn("Launcher #{id} with opts #{opts} did not return a job ID.")
        else
          job_id_hash[id] = {
            job_id: job_id,
            cluster_id: opts[:auto_batch_clusters]
          }
        end
      rescue => e
        error_msg = "Launcher #{id} with opts #{opts} failed to submit. Error: #{e.class}: #{e.message}"
        errors.add("Submit", error_msg)
        Rails.logger.warn(error_msg)
      end
    end
    return job_id_hash unless errors.any?
    nil
  end

  # Build a mapping of input port values from connected output ports
  # Returns: { target_launcher_id => { input_port_key => "value1:value2:..." } }
  def build_port_connections(edges, all_launchers)
    port_values = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = [] } }

    edges.each do |edge|
      from_id = edge["from"]
      to_id = edge["to"]
      from_port_key = edge["fromPort"]
      to_port_key = edge["toPort"]

      next if from_port_key.blank? || to_port_key.blank?

      source_launcher = all_launchers.find { |l| l.id == from_id }
      next unless source_launcher

      output_value = get_port_value(source_launcher, from_port_key, 'output_port')
      next if output_value.blank?

      port_values[to_id][to_port_key] << output_value
    end

    result = {}
    port_values.each do |target_id, ports|
      result[target_id] = {}
      ports.each do |port_key, values|
        result[target_id][port_key] = values.join(" : ")
      end
    end

    result
  end

  def get_port_value(launcher, port_key, port_type)
    # port_key is uppercase ("OUTPUT_VAR") and attribute id is like "auto_environment_variable_output_var"
    normalized_key = port_key.to_s.downcase
    attr_id = "auto_environment_variable_#{normalized_key}"

    attr = launcher.smart_attributes.find do |a|
      a.id.to_s == attr_id && a.opts[:port_type].to_s == port_type
    end

    attr&.value.to_s
  end

  def submit_launcher_params(launcher, dependent_jobs, port_overrides = {})
    launcher_data = launcher.cacheless_attributes.each_with_object({}) do |attr, hash|
      hash[attr.id.to_s] = attr.opts[:value]
    end

    port_overrides.each do |port_key, value|
      normalized_key = port_key.to_s.downcase
      attr_key = "auto_environment_variable_#{normalized_key}"
      
      existing_value = launcher_data[attr_key].to_s
      if existing_value.present?  # append all environment values together with `:` like in Linux Path
        launcher_data[attr_key] = "#{existing_value} : #{value}"
      else
        launcher_data[attr_key] = value
      end
    end
    
    launcher_data["afterok"] = Array(dependent_jobs)
    launcher_data
  end

end
