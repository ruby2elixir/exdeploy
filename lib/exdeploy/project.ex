defmodule Exdeploy.Project do
  require Logger
  alias Exdeploy.Project
  alias Exdeploy.App
  alias Exdeploy.Release

  defstruct [build_path: nil, deploy_path: nil]

  def new(build_path, deploy_path \\ nil) do
    build_path = Path.expand(build_path)
    if deploy_path, do: deploy_path = Path.expand(deploy_path)
    %Project{
      build_path: build_path,
      deploy_path: deploy_path,
    }
  end

  def apps(project) do
    if umbrella?(project) do
      umbrella_apps(project)
    else
      [non_umbrella_app(project)]
    end
  end

  def umbrella_apps_path(%Project{build_path: path}) do
    "#{path}/apps"
  end

  def umbrella_apps_paths(project = %Project{}) do
    "#{umbrella_apps_path(project)}/*"
    |> Path.expand
    |> Path.wildcard
  end

  def umbrella?(project = %Project{}) do
    umbrella_apps_path(project) |> File.dir?
  end

  defp umbrella_apps(project) do
    Enum.map umbrella_apps_paths(project), fn(app_path) ->
      [app_name|_] = String.split(app_path, "/") |> Enum.reverse
      %App{
        path: app_path,
        name: app_name,
        project: project,
        deploy_path: "#{project.deploy_path}/#{app_name}",
      }
    end
  end

  defp non_umbrella_app(project) do
    app_path = project.build_path
    [app_name|_] = String.split(app_path, "/") |> Enum.reverse
    %App{
      path: app_path,
      name: app_name,
      project: project,
      deploy_path: "#{project.deploy_path}/#{app_name}"
    }
  end

  def deploy(project) do
    deploy(project, [])
  end

  def deploy(project, options) when is_list(options) do
    Enum.each apps(project), fn(app) ->
      release = App.latest_release(app)
      cond do
        App.never_deployed?(app) ->
          release |> Release.install(options)
        App.latest_version(app) > App.current_version(app) ->
          if App.running?(app) do
            release |> Release.upgrade(options)
          else
            release |> Release.install(options)
          end
        true ->
          Logger.warn "#{app.name}: No version change, nothing to deploy"
      end
      App.start(app)
    end
  end

  def deploy(build_path, deploy_path) when is_binary(deploy_path) do
    deploy(build_path, deploy_path, [])
  end

  def deploy(build_path, deploy_path, options) do
    Project.new(build_path, deploy_path) |> deploy(options)
  end

  def build(project, options) do
    if is_binary(project) do
      Project.new(project) |> build(options)
    else
      apps(project) |> Enum.map(&App.full_build(&1, options))
    end
  end

  def clean_rel(project) do
    apps(project)
    |> Enum.map(&App.rm_rel/1)
  end

  def releases(project) do
    apps(project)
    |> Enum.map(&App.releases/1)
    |> List.flatten
  end

  def latest_releases(project) do
    apps(project)
    |> Enum.map(&App.latest_release/1)
  end

  def start(project) do
    apps(project)
    |> Enum.map(&App.start/1)
  end

  def stop(project) do
    apps(project)
    |> Enum.map(&App.stop/1)
  end

  def restart(project) do
    apps(project)
    |> Enum.map(&App.restart/1)
  end

  def running?(project) do
    apps(project)
    |> Enum.any?(&App.running?/1)
  end
end
