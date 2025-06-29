# frozen_string_literal: true

class Workflow
  include ActiveModel::Model

  class << self
    def workflows_file(project_dir)
      workflows_dir = Pathname.new("#{project_dir}/.ondemand/workflows")
      # TODO: Later use <workflow_id>.yml to get list of all workflows
      file = workflows_dir.join("workflow.yml")

      FileUtils.mkdir_p(workflows_dir)
      FileUtils.touch(workflows_dir.join("workflow.yml")) unless file.exist?

      file
    end

    def all(project_id)
      project = Project.find(project_id)
      project_dir = project.directory
      f = File.read(workflows_file(project_dir))
      YAML.safe_load(f).to_h.map do |id, workflow_name|
        Workflow.new({ id: id, name: workflow_name })
      end
    rescue StandardError, Exception => e
      Rails.logger.warn("cannot read #{project_dir}/.ondemand/workflows/workflow.yml due to error #{e}")
      {}
    end

    def next_id
      SecureRandom.alphanumeric(8).downcase
    end

    def find(id)
      # TODO: Complete it
    end
  end
  
  attr_reader :id, :name, :description, :project_id, :project_dir

  def initialize(attributes = {})
    @id = attributes[:id]
    @name = attributes[:name]
    @description = attributes[:description]
    @project_id = attributes[:project_id]
    project = Project.find(@project_id)
    @project_dir = project.directory unless project.nil?
  end

  def to_h
    {
      :id => id,
      :name => name,
      :description => description,
    }
  end

  def save
    return false unless valid?(:create)

    # SET DEFAULTS
    @id = Workflow.next_id if id.blank?

    add_to_workflow(:save) && save_manifest(:save)
  end

  def save_manifest(operation)
    file = Workflow.workflows_dir.join("#{@id}.yml")
    FileUtils.touch(file) unless file.exist?
    Pathname(file).write(to_h.deep_stringify_keys.compact.to_yaml)

    true
  rescue StandardError => e
    errors.add(operation, I18n.t('dashboard.jobs_project_save_error', path: file))
    Rails.logger.warn "Cannot save workflow manifest: #{file} with error #{e.class}:#{e.message}"
    false
  end

  def add_to_workflow(operation)
    f = File.read(Workflow.workflows_file(project_dir))
    new_table = YAML.safe_load(f).to_h.merge(Hash[id, name.to_s])
    File.write(Workflow.workflows_file(project_dir), new_table.to_yaml)
    true
  rescue StandardError => e
    errors.add(operation, "Cannot update workflow lookup file with error #{e.class}:#{e.message}")
    false
  end

  def collect_errors
    errors.map(&:message).join(', ')
  end

  # TODO: Add logic to save the DAG relation between launchers like array of <launcher #1, launcher #2>

  # TODO: Add logic to save launcher pairs in the <workflow_id>.yml file and use it in def show() from workflow_controller

end