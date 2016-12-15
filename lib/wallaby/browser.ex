defmodule Wallaby.Browser do
  alias Wallaby.Element
  alias Wallaby.Phantom.Driver
  alias Wallaby.StatelessQuery
  alias Wallaby.StatelessQuery.ErrorMessage
  alias Wallaby.Session

  @type t :: any()

  @opaque session :: Session.t
  @opaque element :: Element.t

  @type parent :: element
                | session
  @type locator :: StatelessQuery.t()
                 | String.t
  @type opts :: StatelessQuery.opts()

  @default_max_wait_time 3_000

  @doc """
  Attempts to synchronize with the browser. This is most often used to
  execute queries repeatedly until it either exceeds the time limit or
  returns a success.

  ## Note

  It is possible that this function never halts. Whenever we experience a stale
  reference error we retry the query without checking to see if we've run over
  our time. In practice we should eventually be able to query the dom in a stable
  state. However, if this error does continue to occur it will cause wallaby to
  loop forever (or until the test is killed by exunit).
  """
  @opaque result :: {:ok, any()} | {:error, any()}
  @spec retry((() -> result), timeout) :: result()

  def retry(f, start_time \\ current_time) do
    case f.() do
      {:ok, result} ->
        {:ok, result}
      {:error, :stale_reference} ->
        retry(f, start_time)
      {:error, e} ->
        if max_time_exceeded?(start_time) do
          {:error, e}
        else
          retry(f, start_time)
        end
    end
  end

  @doc """
  Fills in a "fillable" element with text. Input elements are looked up by id, label text,
  or name.
  """
  @spec fill_in(element, opts) :: element
  @spec fill_in(parent, StatelessQuery.t, with: String.t) :: parent
  @spec fill_in(parent, locator, opts) :: parent

  def fill_in(parent, locator, [{:with, value} | _]=opts) when is_number(value) do
    fill_in(parent, locator,  Keyword.merge(opts, [with: to_string(value)]))
  end
  def fill_in(parent, locator, [{:with, value} | _]=opts) when is_binary(value) do
    parent
    |> find(StatelessQuery.fillable_field(locator, opts))
    |> fill_in(with: value)

    parent
  end
  def fill_in(%Element{}=element, with: value) when is_binary(value) do
    element
    |> clear
    |> set_value(value)

    element
  end

  @doc """
  Chooses a radio button based on id, label text, or name.
  """
  @spec choose(element) :: element
  @spec choose(parent, StatelessQuery.t) :: parent
  @spec choose(parent, locator, opts) :: parent

  def choose(parent, locator, opts\\[]) when is_binary(locator) do
    parent
    |> find(StatelessQuery.radio_button(locator, opts))
    |> click

    parent
  end
  def choose(%Element{}=element) do
    click(element)
  end

  @doc """
  Checks a checkbox based on id, label text, or name.
  """
  @spec check(Element.t) :: Element.t
  @spec check(parent, StatelessQuery.t) :: parent
  @spec check(parent, locator, opts) :: parent

  def check(parent, locator, opts\\[]) do
    parent
    |> find(StatelessQuery.checkbox(locator, opts))
    |> check

    parent
  end

  @doc """
  Unchecks a checkbox based on id, label text, or name.
  """
  @spec uncheck(Element.t) :: Element.t
  @spec uncheck(parent, StatelessQuery.t) :: parent
  @spec uncheck(parent, locator, opts) :: parent

  def uncheck(parent, locator, opts\\[]) do
    parent
    |> find(StatelessQuery.checkbox(locator, opts))
    |> uncheck

    parent
  end

  @doc """
  Selects an option from a select box. The select box can be found by id, label
  text, or name. The option can be found by its text.
  """
  @spec select(Element.t) :: Element.t
  @spec select(parent, StatelessQuery.t) :: parent
  @spec select(parent, StatelessQuery.t, from: StatelessQuery.t) :: parent
  @spec select(parent, locator, opts) :: parent

  def select(parent, locator, [option: option_text]=opts) do
    parent
    |> find(StatelessQuery.select(locator, opts))
    |> find(StatelessQuery.option(option_text, []))
    |> click

    parent
  end

  @doc """
  Clicks the matching link. Links can be found based on id, name, or link text.
  """
  @spec click_link(parent, StatelessQuery.t) :: parent
  @spec click_link(parent, locator, opts) :: parent

  def click_link(parent, locator, opts\\[]) do
    parent
    |> find(StatelessQuery.link(locator, opts))
    |> click

    parent
  end

  @doc """
  Clicks the matching button. Buttons can be found based on id, name, or button text.
  """
  @spec click_button(parent, StatelessQuery.t) :: parent
  @spec click_button(parent, locator, opts) :: parent

  def click_button(parent, locator, opts\\[]) do
    parent
    |> find(StatelessQuery.button(locator, opts))
    |> click

    parent
  end

  @doc """
  Clicks on the matching button. Alias for `click_button`.
  """
  @spec click_on(parent, locator, opts) :: parent

  def click_on(parent, locator, opts\\[]) do
    click_button(parent, locator, opts)
  end

  # @doc """
  # Clears an input field. Input elements are looked up by id, label text, or name.
  # The element can also be passed in directly.
  # """
  # @spec clear(Session.t, query) :: Session.t
  # def clear(session, query) when is_binary(query) do
  #   session
  #   |> find({:fillable_field, query})
  #   |> clear()
  # end

  @doc """
  Attaches a file to a file input. Input elements are looked up by id, label text,
  or name.
  """
  @spec attach_file(parent, locator, opts) :: parent

  def attach_file(parent, locator, [{:path, value} | _]=opts) do
    path = :filename.absname(value)

    parent
    |> find(StatelessQuery.file_field(locator, opts))
    |> fill_in(with: path)

    parent
  end

  @doc """
  Deletes a session.
  """
  @spec delete(t) :: :ok

  def delete(session) do
    Driver.execute_script(session, "localStorage.clear()")
    Driver.delete(session)
    :ok
  end

  @doc """
  Takes a screenshot of the current window.
  Screenshots are saved to a "screenshots" directory in the same directory the
  tests are run in.
  """
  @spec take_screenshot(Element.t | t) :: Element.t | t

  def take_screenshot(screenshotable) do
    image_data =
      screenshotable
      |> Driver.take_screenshot

    path = path_for_screenshot
    File.write! path, image_data

    Map.update(screenshotable, :screenshots, [], &(&1 ++ [path]))
  end

  @doc """
  Sets the size of the sessions window.
  """
  @spec set_window_size(t, pos_integer, pos_integer) :: t

  def set_window_size(session, width, height) do
    {:ok, _} = Driver.set_window_size(session, width, height)
    session
  end

  @doc """
  Gets the size of the session's window.
  """
  @spec get_window_size(t) :: %{String.t => pos_integer, String.t => pos_integer}

  def get_window_size(session) do
    {:ok, size} = Driver.get_window_size(session)
    size
  end

  @doc """
  Gets the current url of the session
  """
  @spec get_current_url(t) :: String.t

  def get_current_url(session) do
    {:ok, url} = Driver.current_url(session)
    url
  end

  @doc """
  Gets the current path of the session
  """
  @spec get_current_path(t) :: String.t

  def get_current_path(session) do
    URI.parse(get_current_url(session)).path
  end

  @doc """
  Gets the title for the current page
  """
  @spec page_title(t) :: String.t

  def page_title(session) do
    {:ok, title} = Driver.page_title(session)
    title
  end

  @doc """
  Executes javascript synchoronously, taking as arguments the script to execute,
  and optionally a list of arguments available in the script via `arguments`
  """
  @spec execute_script(t, String.t, list) :: t

  def execute_script(session, script, arguments \\ []) do
    {:ok, value} = Driver.execute_script(session, script, arguments)
    value
  end

  @doc """
  Sends a list of key strokes to active element. Keys should be provided as a
  list of atoms, which are automatically converted into the corresponding key
  codes.

  For a list of available key codes see `Wallaby.Helpers.KeyCodes`.

  ## Example

      iex> Wallaby.Session.send_keys(session, [:enter])
      iex> Wallaby.Session.send_keys(session, [:shift, :enter])
  """
  @spec send_keys(t, list(atom)) :: t

  def send_keys(session, keys) when is_list(keys) do
    {:ok, _} = Driver.send_keys(session, keys)
    session
  end

  @doc """
  Sends text characters to the active element
  """
  @spec send_text(t, String.t) :: t

  def send_text(session, text) do
    {:ok, _} = Driver.send_text(session, text)
    session
  end

  @doc """
  Retrieves the source of the current page.
  """
  @spec page_source(t) :: String.t

  def page_source(session) do
    {:ok, source} = Driver.page_source(session)
    source
  end

  defp request_url(path) do
    base_url <> path
  end

  defp base_url do
    Application.get_env(:wallaby, :base_url) || ""
  end

  defp path_for_screenshot do
    File.mkdir_p!(screenshot_dir)
    "#{screenshot_dir}/#{:erlang.system_time}.png"
  end

  defp screenshot_dir do
    Application.get_env(:wallaby, :screenshot_dir) || "#{File.cwd!()}/screenshots"
  end

  @doc """
  Sets the value of an element.
  """
  def set_value(element, value) do
    {:ok, _} = Driver.set_value(element, value)
  end

  @doc """
  Clears an input field. Input elements are looked up by id, label text, or name.
  The element can also be passed in directly.
  """
  @spec clear(Element.t) :: Session.t

  def clear(element) do
    {:ok, _} = Driver.clear(element)
    element
  end

  @doc """
  Clicks a element.
  """
  @spec click(t) :: Session.t

  def click(element) do
    Driver.click(element)
    element
  end

  def check(%Element{}=element) do
    unless checked?(element) do
      click(element)
    end
    element
  end

  def uncheck(%Element{}=element) do
    if checked?(element) do
      click(element)
    end
    element
  end

  @doc """
  Gets the Element's text value.
  """
  @spec text(t) :: String.t

  def text(element) do
    case Driver.text(element) do
      {:ok, text} ->
        text
      {:error, :stale_reference_error} ->
        raise Wallaby.StaleReferenceException
    end
  end

  @doc """
  Gets the value of the elements attribute.
  """
  @spec attr(t, String.t) :: String.t | nil

  def attr(element, name) do
    {:ok, attribute} = Driver.attribute(element, name)
    attribute
  end

  @doc """
  Gets the selected value of the element.

  For Checkboxes and Radio buttons it returns the selected option.
  """
  @spec selected(t) :: any()

  def selected(element) do
    {:ok, value} = Driver.selected(element)
    value
  end

  @doc """
  Checks if the element has been selected.
  """
  @spec checked?(t) :: boolean()

  def checked?(%Element{}=element) do
    selected(element) == true
  end

  @doc """
  Checks if the element has been selected. Alias for checked?(element)
  """
  @spec selected?(t) :: boolean()

  def selected?(%Element{}=element) do
    checked?(element)
  end

  @doc """
  Checks if the element is visible on the page
  """
  @spec visible?(t) :: boolean()

  def visible?(%Element{}=element) do
    Driver.displayed!(element)
  end

  @doc """
  Finds a specific DOM element on the page based on a css selector. Blocks until
  it either finds the element or until the max time is reached. By default only
  1 element is expected to match the query. If more elements are present then a
  count can be specified. By default only elements that are visible on the page
  are returned.

  Selections can be scoped by providing a Element as the locator for the query.
  """
  def find(parent, css, opts) when is_binary(css) do
    find(parent, StatelessQuery.css(css, opts))
  end
  def find(parent, css) when is_binary(css) do
    find(parent, StatelessQuery.css(css))
  end
  def find(parent, %StatelessQuery{}=query) do
    case execute_query(parent, query) do
      {:ok, query} ->
        StatelessQuery.result(query)

      {:error, {:not_found, result}} ->
        query = %StatelessQuery{query | result: result}

        if Wallaby.screenshot_on_failure? do
          take_screenshot(parent)
        end

        case validate_html(parent, query) do
          {:ok, _} ->
            raise Wallaby.QueryError, ErrorMessage.message(query, :not_found)
          {:error, html_error} ->
            raise Wallaby.QueryError, ErrorMessage.message(query, html_error)
        end

      {:error, e} ->
        if Wallaby.screenshot_on_failure? do
          take_screenshot(parent)
        end

        raise Wallaby.QueryError, ErrorMessage.message(query, e)
    end
  end

  @doc """
  Finds all of the DOM elements that match the css selector. If no elements are
  found then an empty list is immediately returned.
  """
  def all(parent, css) when is_binary(css) do
    find(parent, StatelessQuery.css(css, minimum: 0))
  end
  def all(parent, %StatelessQuery{}=query) do
    find(parent, %StatelessQuery{query | conditions: Keyword.merge(query.conditions, [count: nil, minimum: 0])})
  end

  @doc """
  Matches the Element's value with the provided value.
  """
  # @spec has_value?(t, any()) :: boolean()

  def has_value?(%Element{}=element, value) do
    attr(element, "value") == value
  end

  @doc """
  Matches the Element's content with the provided text and raises if not found
  """
  # @spec assert_text(t, String.t) :: boolean()

  def assert_text(%Element{}=element, text) when is_binary(text) do
    cond do
      has?(element, StatelessQuery.text(text)) -> true
      true -> raise Wallaby.ExpectationNotMet, "Text '#{text}' was not found."
    end
  end

  def has?(parent, query) do
    case execute_query(parent, query) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Matches the Element's content with the provided text
  """
  # @spec has_text?(t, String.t) :: boolean()

  def has_text?(%Element{}=element, text) when is_binary(text) do
    try do
      assert_text(element, text)
    rescue
      _e in Wallaby.ExpectationNotMet -> false
    end
  end

  @doc """
  Searches for CSS on the page.
  """
  # @spec has_css?(locator, String.t) :: boolean()

  def has_css?(parent, css) when is_binary(css) do
    parent
    |> Wallaby.Browser.find(Wallaby.StatelessQuery.css(css, count: :any))
    |> Enum.any?
  end

  @doc """
  Searches for css that should not be on the page
  """
  # @spec has_no_css?(locator, String.t) :: boolean()

  def has_no_css?(parent, css) when is_binary(css) do
    parent
    |> Wallaby.Browser.find(Wallaby.StatelessQuery.css(css, count: 0))
    |> Enum.empty?
  end

  @doc """
  Changes the current page to the provided route.
  Relative paths are appended to the provided base_url.
  Absolute paths do not use the base_url.
  """
  @spec visit(t, String.t) :: t

  def visit(session, path) do
    uri = URI.parse(path)

    cond do
      uri.host == nil && String.length(base_url) == 0 ->
        raise Wallaby.NoBaseUrl, path
      uri.host ->
        Driver.visit(session, path)
      true ->
        Driver.visit(session, request_url(path))
    end

    session
  end

  defp validate_html(parent, %{html_validation: :button_type}=query) do
    buttons = all(parent, StatelessQuery.css("button", [text: query.selector]))

    cond do
      Enum.any?(buttons) ->
        {:error, :button_with_bad_type}
      true ->
        {:ok, query}
    end
  end
  defp validate_html(parent, %{html_validation: :bad_label}=query) do
    label_query = StatelessQuery.css("label", text: query.selector)
    labels = all(parent, label_query)

    cond do
      Enum.any?(labels, &(missing_for?(&1))) ->
        {:error, :label_with_no_for}
      label=List.first(labels) ->
        {:error, {:label_does_not_find_field, attr(label, "for")}}
      true ->
        {:ok, query}
    end
  end
  defp validate_html(_, query), do: {:ok, query}

  defp missing_for?(element) do
    attr(element, "for") == nil
  end

  defp validate_visibility(query, elements) do
    visible = StatelessQuery.visible?(query)

    {:ok, Enum.filter(elements, &(visible?(&1) == visible))}
  end

  defp validate_count(query, elements) do
    cond do
      StatelessQuery.matches_count?(query, Enum.count(elements)) ->
        {:ok, elements}
      true ->
        {:error, {:not_found, elements}}
    end
  end

  defp validate_text(query, elements) do
    text = StatelessQuery.inner_text(query)

    if text do
      {:ok, Enum.filter(elements, &(matching_text?(&1, text)))}
    else
      {:ok, elements}
    end
  end

  defp matching_text?(element, text) do
    case Driver.text(element) do
      {:ok, element_text} ->
        element_text =~ ~r/#{Regex.escape(text)}/
      {:error, _} ->
        false
    end
  end

  defp execute_query(parent, query) do
    retry fn ->
      try do
        with {:ok, query}  <- StatelessQuery.validate(query),
             {method, selector} <- StatelessQuery.compile(query),
             {:ok, elements} <- Driver.find_elements(parent, {method, selector}),
             {:ok, elements} <- validate_visibility(query, elements),
             {:ok, elements} <- validate_text(query, elements),
             {:ok, elements} <- validate_count(query, elements),
         do: {:ok, %StatelessQuery{query | result: elements}}
      rescue
        Wallaby.StaleReferenceException ->
          {:error, :stale_reference}
      end
    end
  end

  defp max_time_exceeded?(start_time) do
    current_time - start_time > max_wait_time
  end

  defp current_time do
    :erlang.monotonic_time(:milli_seconds)
  end

  defp max_wait_time do
    Application.get_env(:wallaby, :max_wait_time, @default_max_wait_time)
  end
end
