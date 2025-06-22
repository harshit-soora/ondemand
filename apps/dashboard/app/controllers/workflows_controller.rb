# frozen_string_literal: true

# The controller for apps pages /dashboard/projects/:project_id/workflows/:workflow_id
class WorkflowsController < ApplicationController

  # GET /projects/:id/workflows/:id
  def show
    # TODO: Complete it
  end

  # GET /projects/:id/workflows
  def index
    @project = Project.find(params[:project_id])
    @workflows = Workflow.all(index_params[:project_id])
  end

  # GET /projects/:id/workflows/new
  def new
    @workflow = Workflow.new
  end

  # GET /projects/:id/workflows/edit
  def edit
    # TODO: Complete it
  end

  # PATCH /projects/:id/workflows/patch
  def update
    # TODO: Complete it
  end

  # POST /projects/:id/workflows/
  def create
    @project = Project.find(params[:project_id])
    Workflow.project_dir = @project.directory
    @workflow = Workflow.new(permit_params)

    if @workflow.save
      redirect_to project_workflows_path, notice: I18n.t('dashboard.jobs_workflow_created')
    else
      # TODO: Rename "jobs_project_*"" to "jobs_*" to generalize
      message = if @workflow.errors[:save].empty?
                  I18n.t('dashboard.jobs_project_validation_error')
                else
                  I18n.t(
                    'dashboard.jobs_project_generic_error', error: @workflow.collect_errors
                  )
                end
      flash.now[:alert] = message
      render :new
    end
  end

  # DELETE /projects/:id/workflows/:id
  def destroy
    # TODO: Complete it
  end

  # POST /projects/:project_id/workflows/:id/submit
  def submit
    # TODO: Add logic to call submit of each launcher based upon dependency DAG graph
  end

  private

  def index_params
    params.permit(:project_id)

  def permit_param
    params
      .require(:workflow)
      .permit(:name, :description, :id)
  end

end