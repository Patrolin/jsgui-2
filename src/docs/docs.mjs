import { div, span, svg, button, input, useState, renderBody, rerender, webgl, glUseProgram, glSetBuffer } from "src/jsgui/jsgui.mjs";

/**
 * @param {Component} header */
function headerLeft(header) {
  svg(
    header,
    { fontSize: 24 },
    `<svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 0 24 24" width="24" focusable="false"><path d="M21 6H3V5h18v1zm0 5H3v1h18v-1zm0 6H3v1h18v-1z"></path></svg>`
  );
}
/**
 * @param {Component} header */
function headerMiddle(header) {
  const searchWrapper = div(header, { flex: "x" });
  input(searchWrapper, "text", {
    height: 40,
    borderRadius: "20px 0 0 20px",
    border: "1px solid rgb(48, 48, 48)",
    background: "none",
    padding: "0 0 0 16px",
    fontFamily: "Roboto, Arial, sans-serif",
    fontSize: 16,
    color: "white",
  });
  const searchButton = div(searchWrapper, {
    width: 64,
    height: 40,
    borderRadius: "0 20px 20px 0",
    background: "rgb(48, 48, 48)",
    flex: "x",
  });
  svg(
    searchButton,
    { fontSize: 24 },
    `<svg xmlns="http://www.w3.org/2000/svg" fill="currentColor" height="24" viewBox="0 0 24 24" width="24" focusable="false"><path clip-rule="evenodd" d="M16.296 16.996a8 8 0 11.707-.708l3.909 3.91-.707.707-3.909-3.909zM18 11a7 7 0 00-14 0 7 7 0 1014 0z" fill-rule="evenodd"></path></svg>`
  );

  const voiceButton = div(searchWrapper, {
    margin: "0 0 0 12px",
    width: 40,
    height: 40,
    borderRadius: 20,
    background: "rgb(48, 48, 48)",
    flex: "x",
  });
  svg(
    voiceButton,
    { fontSize: 24 },
    `<svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 0 24 24" width="24" focusable="false"><path d="M12 3c-1.66 0-3 1.37-3 3.07v5.86c0 1.7 1.34 3.07 3 3.07s3-1.37 3-3.07V6.07C15 4.37 13.66 3 12 3zm6.5 9h-1c0 3.03-2.47 5.5-5.5 5.5S6.5 15.03 6.5 12h-1c0 3.24 2.39 5.93 5.5 6.41V21h2v-2.59c3.11-.48 5.5-3.17 5.5-6.41z"></path></svg>`
  );
}
/**
 * @param {Component} header */
function headerRight(header) {
  div(header);
}
/**
 * @param {Component} body */
function App(body) {
  const state = useState(body, "App", {
    lineCount: 2,
  });

  const header = div(body, { width: "100%", height: 56, padding: "0 16px", flex: "x", flexAlign: "justify" });

  headerLeft(header);
  headerMiddle(header);
  headerRight(header);

  const main = div(body, { width: "100%", padding: "8px 24px", flex: "x", flexAlign: "start", columnGap: 16 });
  const mainLeft = div(main, { flex: "y" });
  for (let i = 0; i < state.lineCount; i++) {
    span(mainLeft, `Lorem ipsum ${i}`, { width: "100%" });
  }
  for (let i = 0; i < state.lineCount; i++) {
    span(mainLeft, `Dolor amet ${state.lineCount + i}`, { width: "100%" });
  }

  const mainRight = div(main, { flex: "y" });
  if (button(mainRight, "Hello", { width: 64, height: 24 }).pressed) {
    state.lineCount += 1
    rerender();
  }
  webgl(mainRight, {width: 400, height: 400}, {
    programs: {
      gradient: {
        vertex: `
          in vec2 v_position;
          in vec3 v_color;
          out vec3 f_color;
          void main() {
            gl_Position = vec4(v_position, 0, 1);
            f_color = v_color;
          }
        `,
        fragment: `
          in vec3 f_color;
          out vec4 out_color;
          void main() {
            out_color = vec4(f_color, 1);
          }
        `,
      },
      flatColor: {
        vertex: `
          in vec2 v_position;
          void main() {
            gl_Position = vec4(v_position, 0, 1);
          }
        `,
        fragment: `
          uniform mat4x4 u_mat;
          uniform vec3 u_color;
          out vec4 out_color;
          void main() {
            out_color = u_mat * vec4(u_color, 1);
          }
        `,
      },
    },
    render: ({gl, programs}) => {
      // draw blue background
      const flatColor = /** @type {GLProgramInfo} */(programs.flatColor);
      glUseProgram(gl, flatColor);
      glSetBuffer(gl,
        /** @type {GLBufferInfo} */(flatColor.buffers.v_position),
        new Float32Array([
        -1, -1,
        -1, +1,
        +1, +1,
        +1, -1,
      ]));
      gl.uniformMatrix4fv(
        /** @type {WebGLUniformLocation} */(flatColor.uniforms.u_mat),
        false, [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
      ]);
      gl.uniform3f(
        /** @type {WebGLUniformLocation} */(flatColor.uniforms.u_color),
        0, 0.5, 1);
      gl.drawArrays(gl.TRIANGLE_FAN, 0, 4);

      // draw rainbow triangle
      const gradient = /** @type {GLProgramInfo} */(programs.gradient);
      glUseProgram(gl, gradient);
      glSetBuffer(gl,
        /** @type {GLBufferInfo} */(gradient.buffers.v_position),
        new Float32Array([
        0.0,  0.6,
       -0.5, -0.6,
        0.5, -0.6,
      ]));
      glSetBuffer(gl,
        /** @type {GLBufferInfo} */(gradient.buffers.v_color),
        new Float32Array([
        1, 0, 0,
        0, 1, 0,
        0, 0, 1,
      ]));
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    }
  })
}
renderBody(App, { scrollY: true });
