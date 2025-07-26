/**
 * @typedef {Object} Component
 * @property {HTMLElement} element
 * @property {any} state
 * @property {Record<string, Component>} children
 * Internal:
 * @property {boolean} gc
 * @property {number} nextIndex
 * @property {HTMLElement | null} nextChild
 */
/**
 * @typedef {Object} HTMLProps
 * @property {string} [key] - required if you want to dynamically add/remove components with state
 * @property {number | string} [margin]
 * @property {number | string} [minWidth]
 * @property {number | string} [width]
 * @property {number | string} [maxWidth]
 * @property {number | string} [minHeight]
 * @property {number | string} [height]
 * @property {number | string} [maxHeight]
 * @property {number | string} [borderRadius]
 * @property {string} [border]
 * @property {string} [background]
 * @property {number | string} [padding]
 * @property {boolean} [scrollX]
 * @property {boolean} [scrollY]
 * @property {"x" | "x-reverse" | "y" | "y-reverse"} [flex]
 * @property {"center" | "justify" | "start"} [flexAlign]
 * @property {number | string} [columnGap]
 * @property {number | string} [rowGap]
 * @property {string} [fontFamily]
 * @property {string} [fontWeight]
 * @property {number | string} [fontSize]
 * @property {string} [color]
 */
