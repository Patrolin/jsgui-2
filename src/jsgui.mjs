// TODO: background: `color-mix(in srgb, #7f7f7f ${100 - percent}%, ${base_color_right} ${percent}%)`
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
    margin,
    minWidth,
    width,
    maxWidth,
    minHeight,
    height,
    maxHeight,
    borderRadius,
    border,
    background,
    padding,
    columnGap,
    rowGap,
    fontFamily,
    fontWeight,
    fontSize,
    color,
    cssVars = {},
    ...attributes
  } = props;
  const style = {
    margin,
    minWidth,
    width,
    maxWidth,
    minHeight,
    height,
    maxHeight,
    borderRadius,
    border,
    background,
    padding,
    columnGap,
    rowGap,
    fontFamily,
    fontWeight,
    fontSize,
    color,
  };
  for (const [key_camelCase, value] of Object.entries(style)) {
    const key = /** @type {keyof typeof style} */(_camelCaseToKebabCase(key_camelCase));
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
    info = parent.children[key];
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
  if (element == null) return; // NOTE: appending a fragment does nothing

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
 * @param {Component} parent
 * @param {string} key
 * @param {T} defaultState
 * @returns {T} */
export function useState(parent, key, defaultState) {
  if (key == null || key === "") throw "key is required in useState()";
  const info = _getChildInfo(parent, `useState(${key})`, undefined, /** @type {any} */(defaultState));
  const { state } = info;
  return state;
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
 * @param {string} [text]
 * @returns {Component} */
export function span(parent, text, props) {
  const info = getElement(parent, "span", props);
  info.element.textContent = text;
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
  const info = getElement(parent, "button", { flex: "x", ...props });
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
