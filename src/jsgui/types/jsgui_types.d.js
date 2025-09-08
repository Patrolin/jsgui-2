/** TODO: className, events
 * @typedef {Object} Component
 * @property {Record<string, Component>} children
 * @property {HTMLElement} element
 * @property {any} state
 * @property {boolean} _gc
 * @property {HTMLElement | null} _nextChild
 * @property {number} _nextIndex
 */
/**
 * @typedef {Record<string, string | number | boolean | undefined | null> & {scrollX?: boolean; scrollY?: boolean; flex?: "x" | "x-reverse" | "y" | "y-reverse"; flexAlign?: "center" | "justify" | "start" | "scroll"}} HTMLAttributes
 */
/**
 * @typedef {Record<string, string | number | undefined | null>} CSSVars
 */
/**
 * @typedef {Object} HTMLProps
 * @property {string} [key] - required if you want to dynamically add/remove components with state
 * @property {string | number} [margin]
 * @property {string | number} [minWidth]
 * @property {string | number} [width]
 * @property {string | number} [maxWidth]
 * @property {string | number} [minHeight]
 * @property {string | number} [height]
 * @property {string | number} [maxHeight]
 * @property {string | number} [flex]
 * @property {string | number} [borderRadius]
 * @property {string} [border]
 * @property {string} [background]
 * @property {string | number} [padding]
 * @property {string | number} [columnGap]
 * @property {string | number} [rowGap]
 * @property {string} [fontFamily]
 * @property {string} [fontWeight]
 * @property {string | number} [fontSize]
 * @property {string} [color]
 * @property {string} [className]
 * @property {HTMLAttributes} [attributes]
 * @property {CSSVars} [cssVars]
 */

/** webgl
 * @typedef {any[] | undefined} WebGLError
 */
/**
 * @typedef {Object} GLBufferInfo
 * @property {number} location
 * @property {number} count // can be >4 for matrices
 * @property {GLenum} type // gl.FLOAT | ...
 * @property {WebGLBuffer} bufferIndex
 */
/**
 * @typedef {Object} GLProgramInfo
 * @property {WebGLProgram} program
 * @property {string} vertex
 * @property {string} fragment
 * @property {WebGLVertexArrayObject} vao
 * @property {Record<string, GLBufferInfo>} buffers
 * @property {Record<string, WebGLUniformLocation>} uniforms
 */
/**
 * @typedef {Object} WebGLState
 * @property {WebGL2RenderingContext} gl
 * @property {Record<string, GLProgramInfo>} programs
 * @property {DOMRect} rect
 * @property {boolean} didCompile
 */
/**
 * @typedef {Object} GLProgramDescriptor
 * @property {string} vertex
 * @property {string} fragment
 */
/**
 * @typedef {Object} WebGLProps
 * @property {Record<string, GLProgramDescriptor>} programs
 * @property {number} [renderResolutionMultiplier]
 * @property {(state: WebGLState) => void} render
 */
