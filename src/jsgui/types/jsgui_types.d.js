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
 * @typedef {Object} HTMLProps
 * @property {string} [key] - required if you want to dynamically add/remove components with state
 * @property {number | string} [margin]
 * @property {number | string} [minWidth]
 * @property {number | string} [width]
 * @property {number | string} [maxWidth]
 * @property {number | string} [minHeight]
 * @property {number | string} [height]
 * @property {number | string} [maxHeight]
 * @property {number | string} [autoSize]
 * @property {number | string} [borderRadius]
 * @property {string} [border]
 * @property {string} [background]
 * @property {number | string} [padding]
 * @property {boolean} [scrollX]
 * @property {boolean} [scrollY]
 * @property {"x" | "x-reverse" | "y" | "y-reverse"} [flex]
 * @property {"center" | "justify" | "start" | "scroll"} [flexAlign]
 * @property {number | string} [columnGap]
 * @property {number | string} [rowGap]
 * @property {string} [fontFamily]
 * @property {string} [fontWeight]
 * @property {number | string} [fontSize]
 * @property {string} [color]
 * @property {string} [className]
 * @property {Record<string, number | string | boolean | undefined | null>} [attributes]
 * @property {Record<string, number | string | undefined | null>} [cssVars]
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
