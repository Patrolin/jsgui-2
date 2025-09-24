/**
 * @param {number | string} value
 * @returns string */
export function addPx(value) {
  return typeof value === "string" ? value : `${value}px`;
}
/**
 * @param {string} value
 * @returns string */
export function _camelCaseToKebabCase(value) {
  return [...value.matchAll(/[a-zA-Z][a-z]*/g)].join("-").toLowerCase();
}

/**
 * @param {HTMLElement} e
 * @param {HTMLProps} [props] */
export function _styleElement(e, props = {}) {
  const {
    key: _,
    className,
    // attributes
    attributes = {},
    cssVars = {},
    flex,
    ...style
  } = props;
  /** @type {any} */(style).flex = flex != null ? String(flex) : undefined;

  if (className) {
    e.className = className;
  } else {
    e.removeAttribute("class");
  }
  for (const [key_camelCase, value] of Object.entries(style)) {
    const key = /** @type {any} */(_camelCaseToKebabCase(key_camelCase));
    if (value != null) e.style[key] = addPx(value);
  }
  for (const [key_camelCase, value] of Object.entries(cssVars)) {
    const key = `--${_camelCaseToKebabCase(key_camelCase)}`;
    if (value != null) {
      e.style.setProperty(key, String(value));
    } else {
      e.style.removeProperty(key);
    }
  }
  for (const [key_camelCase, value] of Object.entries(attributes)) {
    const key = _camelCaseToKebabCase(key_camelCase);
    if (value != null) e.setAttribute(key, String(value));
    else e.removeAttribute(key);
  }
}
/**
 * @param {Component} info
 * @param {boolean} current_gc */
function _removeUnusedComponents(info, current_gc) {
  for (let [key, child_info] of Object.entries(info.children)) {
    _removeUnusedComponents(child_info, current_gc);
    if (child_info._gc !== current_gc) {
      console.log("ayaya.DELETE", info, current_gc);
      child_info.element.remove();
      delete info.children[key];
    }
  }
}
function _recomputeOverflow() {
  for (let e of document.querySelectorAll("*")) {
    if (e.hasAttribute("scroll-x") || e.hasAttribute("scroll-y")) {
      const dataOverflowX = e.scrollWidth > e.clientWidth;
      const dataOverflowY = e.scrollHeight > e.clientHeight;
      e.setAttribute("data-overflow", String(dataOverflowX || dataOverflowY));
    }
  }
}

export const _root_info = /** @type {Component} */(/** @type {unknown} */({ children: {}, element: null, state: {}, _gc: true, _nextChild: null, _nextIndex: 0 }));
/**
 * @param {(parent: Component) => void} Root
 * @param {HTMLProps} bodyProps */
export function renderBody(Root, bodyProps) {
  window.addEventListener("DOMContentLoaded", () => {
    _root_info.element = document.body;
    _root_info.state = { Root, bodyProps };
    _renderNow();
  });
}
function _renderNow() {
  // reset info
  _root_info._gc = !_root_info._gc;
  _root_info._nextIndex = 0;
  _root_info._nextChild = /** @type HTMLElement | null */(_root_info.element.firstElementChild);
  // render Root component
  const { Root, bodyProps } = _root_info.state;
  _styleElement(_root_info.element, bodyProps);
  Root(_root_info);
  _removeUnusedComponents(_root_info, _root_info._gc);
  _recomputeOverflow();
}
export function rerender() {
  if (!_root_info.state.willRerender) {
    _root_info.state.willRerender = true;
    requestAnimationFrame(() => {
      _root_info.state.willRerender = false;
      _renderNow();
    });
  }
}
/**
 * @param {Component} parent
 * @param {string | undefined} key
 * @param {string} [tagName]
 * @param {Record<string, any> | undefined} [defaultState]
 * @returns {Component} */
export function _getChildInfo(parent, key, tagName, defaultState = {}) {
  if (key == null || key === "") {
    key = `${parent._nextIndex++}-${tagName}`;
  }
  let info;
  if (key in parent.children) {
    info = /** @type {Component} */(parent.children[key]);
  } else {
    info = parent.children[key] = /** @type {Component} */ (/** @type {unknown} */ (
      { children: {}, element: null, state: defaultState, _gc: true, _nextChild: null, _nextIndex: 0 }
    ));
  }
  info._gc = parent._gc;
  info._nextIndex = 0;
  return info;
}
/**
 * @param {Component} parent
 * @param {Component} info */
function _appendOrMoveElement(parent, info) {
  const element = info.element;
  if (element == null) return; /* NOTE: things like useState() store data, but have no element */

  info._nextChild = /** @type {HTMLElement | null} */(element.firstElementChild);
  if (element === parent._nextChild) {
    parent._nextChild = /** @type {HTMLElement | null} */(element.nextElementSibling);
  } else {
    parent.element.insertBefore(element, parent._nextChild);
  }
}
/**
 * @param {Component} parent
 * @param {string} tagName
 * @param {HTMLProps} props
 * @returns {Component} */
export function getElement(parent, tagName, props = {}) {
  const info = _getChildInfo(parent, props.key, tagName);
  if (info.element == null) info.element = document.createElement(tagName);
  _styleElement(info.element, props);
  _appendOrMoveElement(parent, info);
  return info;
}

// hooks
/**
 * @template T
 * @typedef {Object} UseStateProps
 * @property {string} [key] - required if you want to call this in arbitrary order, else same rules as React
 * @property {T} value
 */
/**
 * @template T
 * @param {Component} parent
 * @param {UseStateProps<T>} props
 * @returns {T} */
export function useState(parent, props) {
  const {key = "", value} = props;
  const info = _getChildInfo(parent, `useState(${key})`, undefined, /** @type {any} */(value));
  const { state } = info;
  return state;
}
/**
 * @template T
 * @typedef {Object} UseMemoProps
 * @property {string} [key] - required if you want to call this in arbitrary order, else same rules as React
 * @property {() => T} value
 * @property {any[]} [dependOn]
 */
/**
 * @template T
 * @param {Component} parent
 * @param {UseMemoProps<T>} props
 * @returns {T} */
export function useMemo(parent, props) {
  const {key, value, dependOn = []} = props;
  const info = _getChildInfo(parent, `useMemo(${key})`, undefined, {});
  const { state } = info;
  const {prevDependOn = []} = state;
  if (prevDependOn.length !== dependOn.length || dependOn.some((v, i) => v !== prevDependOn[i])) {
    state.value = value();
    state.prevDependOn = dependOn;
  }
  return state.value;
}
/**
 * @template T
 * @typedef {Object} UseGetRequestProps
 * @property {string} [key] - required if you want to call this in arbitrary order, else same rules as React
 * @property {NoInfer<T>} [defaultValue]
 * @property {() => Promise<T>} fetch
 * @property {(errorOrResponse: any) => void} [onError]
 * @property {any} [refetchOn]
 */
/**
 * @template T
 * @param {Component} parent
 * @param {UseGetRequestProps<T>} props
 * @returns {[boolean, T, () => void, boolean]} */
export function useGetRequest(parent, props) {
  const {key = "", fetch, onError, refetchOn} = props;
  let defaultValue;
  if (!("defaultValue" in props)) defaultValue = [];
  else {defaultValue = props.defaultValue};
  const state = useState(parent, {
    key: `useGetRequest.${key}`,
    value: {
      prevRefetchOn: /** @type {string | null} */(null),
      loading: true,
      value: /** @type {T} */(defaultValue),
    },
  });
  const refetch = () => {
    if (state.loading === false) {
      state.loading = true;
      rerender();
    }
    Promise.try(fetch).then((response) => {
      state.value = response;
      state.loading = false;
      rerender();
    }).catch(onError);
  }
  const isInitialLoad = state.prevRefetchOn === null;
  const refetchOn_string = JSON.stringify(refetchOn);
  if (refetchOn_string !== state.prevRefetchOn) {
    state.prevRefetchOn = refetchOn_string;
    refetch();
  }
  return [state.loading, state.value, refetch, isInitialLoad];
}

// components
/**
 * @param {Component} parent
 * @param {HTMLProps} [props]
 * @returns {Component} */
export function div(parent, props) {
  return getElement(parent, "div", props);
}
/**
 * @param {Component} parent
 * @param {HTMLProps} [props]
 * @returns {Component} */
export function ul(parent, props) {
  return getElement(parent, "ul", props);
}
/**
 * @param {Component} parent
 * @param {HTMLProps} [props]
 * @returns {Component} */
export function ol(parent, props) {
  return getElement(parent, "ol", props);
}
/**
 * @param {Component} parent
 * @param {HTMLProps} [props]
 * @returns {Component} */
export function li(parent, props) {
  return getElement(parent, "li", props);
}
/**
 * @param {Component} parent
 * @param {HTMLProps} [props]
 * @param {string} [text]
 * @returns {Component} */
export function span(parent, text, props) {
  const info = getElement(parent, "span", props);
  info.element.textContent = /** @type {any} */(text); /* NOTE: this overwrites all child nodes */
  return info;
}
/**
 * @param {Component} parent
 * @param {HTMLProps} [props]
 * @param {string} [text]
 * @returns {Component} */
export function link(parent, text, props) {
  const info = getElement(parent, "a", props);
  if (text) span(info, text); /* NOTE: don't overwrite child nodes */
  return info;
}
/**
 * @param {Component} parent
 * @param {HTMLProps} props
 * @param {string} innerHTML
 * @returns {Component} */
export function svg(parent, props, innerHTML) {
  const info = _getChildInfo(parent, props.key, "svg");
  if (info.state.prevInnerHTML !== innerHTML) {
    const tmp = document.createElement("div");
    tmp.innerHTML = innerHTML;
    info.element = /** @type {HTMLElement}*/(tmp.children[0]);
    info.state.prevInnerHTML = innerHTML;
  }
  _styleElement(info.element, props);
  _appendOrMoveElement(parent, info);
  return info;
}
/**
 * @param {Component} parent
 * @param {HTMLProps} [props]
 * @param {string} [text]
 * @returns {{info: Component, pressed: boolean}} */
export function button(parent, text, props) {
  const info = getElement(parent, "button", { attributes: {flex: "x", ...props?.attributes}, ...props });
  if (text != null) span(info, text, { key: "button-text" }); // NOTE: browsers are stupid and don't respect textContent on buttons
  const pressed = info.state.pressed;
  info.state.pressed = false;
  info.element.onclick = () => {
    info.state.pressed = true;
    rerender();
  };
  return { info, pressed };
}
/**
 * @param {Component} parent
 * @param {string} type
 * @param {HTMLProps} [props]
 * @returns {Component} */
export function input(parent, type, props) {
  const info = getElement(parent, "input", props); // TODO: handle events
  info.element.setAttribute("type", type);
  return info;
}
/**
 * @param {Component} parent
 * @param {HTMLProps} [props]
 * @returns {Component} */
export function textarea(parent, props) {
  return getElement(parent, "textarea", props); // TODO: handle events
}

// router utils
/**
 * @param {string} path
 * @returns {string} */
export function removeTrailingSlashes(path) {
  let j = path.length;
  for (; path[j-1] === "/"; j--) {}
  return path.slice(0, j);
}
/**
 * @template Route
 * @param {Route[]} routes
 * @param {string} [ignorePrefix]
 * @returns {Route | undefined} */
export function findMatchingRoute(routes, ignorePrefix) {
  let currentPath = window.location.pathname;
  if (ignorePrefix && currentPath.startsWith(ignorePrefix)) {
    currentPath = currentPath.slice(ignorePrefix.length);
  }
  currentPath = removeTrailingSlashes(currentPath);
  return routes.find(route => {
    const routePath = /** @type {any}*/(route).path;
    return removeTrailingSlashes(routePath) === currentPath
  });
}

// webgl lib utils
/**
 * @param {WebGL2RenderingContext} gl
 * @param {WebGLShader} shader
 * @param {string} shaderCode
 * @returns {string} */
function glGetShaderLog(gl, shader, shaderCode) {
  const shaderLines = shaderCode.split("\n");
  const rawShaderLog = gl.getShaderInfoLog(shader) ?? "";
  let prevLineNumberToShow = /** @type {number | null} */(null);
  let acc = "";
  for (let logLine of rawShaderLog.split("\n")) {
    const match = logLine.match(/^ERROR: \d+:(\d+)/);
    let lineNumberToShow = /** @type {number | null} */(null);
    if (match != null) {
      lineNumberToShow = +/** @type {string} */(match[1]) - 1;
    }
    if (prevLineNumberToShow != null && prevLineNumberToShow !== lineNumberToShow) {
      const line = (shaderLines[prevLineNumberToShow] ?? "").trim()
      prevLineNumberToShow = lineNumberToShow;
      acc += `  ${line}\n${logLine}\n`;
    } else {
      prevLineNumberToShow = lineNumberToShow;
      acc += `${logLine}\n`;
    }
  }
  return acc;
}
/**
 * @param {WebGL2RenderingContext} gl
 * @param {WebGLProgram} program
 * @param {number} shaderType
 * @param {string} shaderCode
 * @returns {WebGLError} */
function glCompileShader(gl, program, shaderType, shaderCode) {
  const shader = gl.createShader(shaderType);
  while (1) {
    if (!shader) break;
    gl.shaderSource(shader, shaderCode);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) break;
    gl.attachShader(program, shader);
    return;
  }
  const ShaderTypeName = /** @type {Record<number, string>} */({
    [gl.VERTEX_SHADER]: ".VERTEX_SHADER",
    [gl.FRAGMENT_SHADER]: ".FRAGMENT_SHADER",
  });
  const shaderLog = glGetShaderLog(gl, /** @type {WebGLShader} */(shader), shaderCode);
  return [
    `Could not compile shader:\n${shaderLog}`,
    {
      program,
      shaderType: ShaderTypeName[shaderType] ?? shaderType,
      shaderCode,
      shader,
    }
  ]
}
/**
 * @param {WebGL2RenderingContext} gl
 * @param {GLProgramInfo} programInfo
 * @returns {WebGLError} */
function glCompileProgram(gl, programInfo) {
  const {program, vertex, fragment} = programInfo;
  let error = glCompileShader(gl, program, gl.VERTEX_SHADER, vertex);
  if (error) return error;

  error = glCompileShader(gl, program, gl.FRAGMENT_SHADER, fragment);
  if (error) return error;

  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    const programLog = gl.getProgramInfoLog(program);
    return [`Error linking shader program:\n${programLog}`, {program}]
  }
  gl.useProgram(program);
}
/**
 * @param {WebGL2RenderingContext} gl
 * @param {GLenum} flatType
 * @returns {[GLenum, number]} */
function glDecodeVertexAttributeType(gl, flatType) {
  switch (flatType) {
  /* WebGL */
  case gl.FLOAT:
    return [gl.FLOAT, 1];
  case gl.FLOAT_VEC2:
    return [gl.FLOAT, 2];
  case gl.FLOAT_VEC3:
    return [gl.FLOAT, 3];
  case gl.FLOAT_VEC4:
    return [gl.FLOAT, 4];
  case gl.FLOAT_MAT2:
    return [gl.FLOAT, 4];
  case gl.FLOAT_MAT3:
    return [gl.FLOAT, 9];
  case gl.FLOAT_MAT4:
    return [gl.FLOAT, 16];
  // NOTE: non-square matrices are only valid as uniforms
  /* WebGL2 */
  case gl.INT:
    return [gl.INT, 1];
  case gl.INT_VEC2:
    return [gl.INT, 2];
  case gl.INT_VEC3:
    return [gl.INT, 3];
  case gl.INT_VEC4:
    return [gl.INT, 4];
  case gl.UNSIGNED_INT:
    return [gl.UNSIGNED_INT, 1];
  case gl.UNSIGNED_INT_VEC2:
    return [gl.UNSIGNED_INT, 2];
  case gl.UNSIGNED_INT_VEC3:
    return [gl.UNSIGNED_INT, 3];
  case gl.UNSIGNED_INT_VEC4:
    return [gl.UNSIGNED_INT, 4];
  }
  console.error('Uknown vertexAttribute type:', {flatType});
  return [-1, -1];
}
// webgl user utils
/**
 * @param {WebGL2RenderingContext} gl
 * @param {GLProgramInfo} programInfo */
export function glUseProgram(gl, programInfo) {
  gl.useProgram(programInfo.program);
  gl.bindVertexArray(programInfo.vao);
}
/**
 * @param {WebGL2RenderingContext} gl
 * @param {GLBufferInfo} bufferInfo
 * @param {any} data */
export function glSetBuffer(gl, bufferInfo, data) {
  const {location, count, type, bufferIndex} = bufferInfo;
  gl.bindBuffer(gl.ARRAY_BUFFER, bufferIndex);
  gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);

  const FLOAT_SIZE = 4; // we are assuming `#precision highp float;`
  if (type === gl.FLOAT) {
    let currentLocation = location;
    let remainingCount = count;
    const stride = count * FLOAT_SIZE;
    let currentOffset = 0;
    while (remainingCount >= 4) {
      gl.enableVertexAttribArray(currentLocation);
      gl.vertexAttribPointer(currentLocation++, 4, type, false, stride, currentOffset);
      remainingCount -= 4;
      currentOffset += 4 * FLOAT_SIZE;
    }
    if (remainingCount > 0) {
      gl.enableVertexAttribArray(currentLocation);
      gl.vertexAttribPointer(currentLocation++, remainingCount, type, false, stride, currentOffset);
    }
  } else {
    gl.enableVertexAttribArray(location);
    gl.vertexAttribIPointer(location, count, type, 0, 0);
  }
}

// webgl component
/**
 * @param {Component} parent
 * @param {any} props
 * @param {WebGLProps} webglProps */
export function webgl(parent, props, webglProps) {
  const {
    programs,
    renderResolutionMultiplier = 1.0,
    render = ({gl}) => {
      gl.clearColor(0.0, 0.0, 0.0, 1.0);
      gl.clear(gl.COLOR_BUFFER_BIT);
    }} = webglProps;
  const info = getElement(parent, "canvas", props);
  const node = /** @type {HTMLCanvasElement} */(info.element);
  // TODO: type check the state
  const state = useState(info, {
    value: /** @type {any} */({
      gl: null,
      programs: null,
      rect: new DOMRect(),
      didCompile: false,
    }),
  });
  if (state.gl == null) {
    const gl = node.getContext("webgl2");
    if (!gl) return;
    state.gl = gl;
    // init shaders
    state.programs = {};
    const DEFAULT_SHADER_VERSION = "#version 300 es\n";
    const DEFAULT_FLOAT_PRECISION = "precision highp float;\n"
    /**
     * @param {string} headerCode
     * @param {string} shaderCode
     */
    const addShaderHeader = (headerCode, shaderCode) => {
      return shaderCode.trimStart().startsWith("#version") ? shaderCode : headerCode + shaderCode
    }
    for (let [k, _programInfo] of Object.entries(programs)) {
      const programInfo = /** @type {GLProgramInfo}*/(_programInfo);
      state.programs[k] = programInfo;
      // compile
      programInfo.program = gl.createProgram();
      programInfo.vertex = addShaderHeader(DEFAULT_SHADER_VERSION, programInfo.vertex);
      programInfo.fragment = addShaderHeader(DEFAULT_SHADER_VERSION + DEFAULT_FLOAT_PRECISION, programInfo.fragment);
      let error = glCompileProgram(gl, programInfo);
      if (error) {
        console.error(...error);
        break;
      }
      state.didCompile = true;
      // init vertex buffers
      programInfo.vao = gl.createVertexArray(); // vao means vertexBuffer[]
      gl.bindVertexArray(programInfo.vao);
      programInfo.buffers = {};
      const vertexBufferCount = gl.getProgramParameter(programInfo.program, gl.ACTIVE_ATTRIBUTES);
      for (let i = 0; i < vertexBufferCount; i++) {
        const vertexAttribute = gl.getActiveAttrib(programInfo.program, i);
        if (vertexAttribute == null) {
          console.error(`Couldn't get vertexAttribute:`, {i});
          continue
        }
        const vertexAttributeLocation = gl.getAttribLocation(programInfo.program, vertexAttribute.name);
        if (vertexAttributeLocation == null) {
          console.error(`Couldn't get vertexAttribute location:`, {i, vertexAttribute});
          continue
        }
        const [type, count] = glDecodeVertexAttributeType(gl, vertexAttribute.type);
        programInfo.buffers[vertexAttribute.name] = {
          location: vertexAttributeLocation,
          count,
          type,
          bufferIndex: gl.createBuffer(),
        };
      }
      // get uniform locations
      programInfo.uniforms = {};
      const uniformCount = gl.getProgramParameter(programInfo.program, gl.ACTIVE_UNIFORMS);
      for (let i = 0; i < uniformCount; i++) {
        const uniform = gl.getActiveUniform(programInfo.program, i);
        if (uniform == null) {
          console.error(`Couldn't get uniform:`, {i});
          continue
        }
        const uniformLocation = gl.getUniformLocation(programInfo.program, uniform.name);
        if (uniformLocation == null) {
          console.error(`Couldn't get uniform location:`, {i, uniform});
          continue
        }
        programInfo.uniforms[uniform.name] = uniformLocation;
      }
    }
  }

  // autosize canvas
  const rect = node.getBoundingClientRect();
  rect.width *= renderResolutionMultiplier;
  rect.height *= renderResolutionMultiplier;
  node.width = rect.width;
  node.height = rect.height;
  state.rect = rect;
  // render
  const {gl, didCompile} = state;
  if (didCompile && gl != null) {
    gl.viewport(0, 0, rect.width, rect.height);
    render(state);
  }
}
