/*
 * simple_example.c
 *
 * Copyright (c) 2011 Rickard Edström
 * Copyright (c) 2011 Sebastian Ärleryd
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "gdt/gdt.h"
#include "gdt/gdt_gles2.h"
#include <string.h>
#include <unistd.h>

string_t simpleVertexShader = "                               \
uniform vec2 offset;                                          \
attribute vec4 position;                                      \
void main(void) {                                             \
    gl_Position = position + vec4(offset.x, offset.y, 0, 0);  \
}                                                             \
";

string_t redFragmentShader = "         \
void main(void) {                      \
    gl_FragColor = vec4(1, 0, 0, 1);   \
}                                      \
";

string_t TAG = "simple_example";
float _x = -0.5;
float _y = 0.5;
int _width;
int _height;
GLuint _offsetUniform;
#define LOG(args...) gdt_log(LOG_NORMAL, TAG, args)
#define SIZE 0.3
#define ASSERT(COND) if (!(COND)) gdt_fatal(TAG, "Assertion failed in %s (%s)", __PRETTY_FUNCTION__, #COND)

typedef enum {
	STATE_NOT_INITIALIZED,
	STATE_INITIALIZED_NOT_VISIBLE,
	STATE_INITIALIZED_VISIBLE_NOT_ACTIVE,
	STATE_INITIALIZED_VISIBLE_ACTIVE,
} state_t;

state_t _state = STATE_NOT_INITIALIZED;

static GLuint compileShader(string_t shaderCode, GLenum type) {
    GLuint shader = glCreateShader(type);

    int len = strlen(shaderCode);
    glShaderSource(shader, 1, &shaderCode, &len);

    glCompileShader(shader);

    GLint result;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &result);
    if (result == GL_FALSE) {
        gdt_fatal(TAG, "Error compiling shader");
    }

    return shader;
}

static GLuint linkProgram() {
    GLuint vertexShader = compileShader(simpleVertexShader, GL_VERTEX_SHADER);
    GLuint fragmentShader = compileShader(redFragmentShader, GL_FRAGMENT_SHADER);

    GLuint program = glCreateProgram();

    glAttachShader(program, vertexShader);
    glAttachShader(program, fragmentShader);

    glLinkProgram(program);

    GLint result;
    glGetProgramiv(program, GL_LINK_STATUS, &result);
    if (result == GL_FALSE) {
        gdt_fatal(TAG, "Error linking program");
    }

    return program;
}

static bool inside_the_square(float x, float y) {
    return (x > _x && x < (_x + SIZE)) && (y > _y && y < (_y + SIZE));
}

static void move(float x, float y) {
    _x = x - SIZE / 2;
    _y = y - SIZE / 2;
}

static void on_touch(touch_type_t what, int screenX, int screenY) {
    static int state = 0;

    float x = 2 * screenX / (float) _width  - 1;
    float y = 2 * screenY / (float) _height - 1;

    if (state) {
        switch (what) {
        case TOUCH_MOVE:
            move(x, y);
            break;
        case TOUCH_UP:
            state = 0;
            break;
        default: {}
        }
    } else {
        switch (what) {
        case TOUCH_DOWN:
            if (inside_the_square(x, y)) {
                state = 1;
                move(x, y);
            }
            break;
        default: {}
        }
    }
}

void gdt_hook_initialize() {
	ASSERT(_state == STATE_NOT_INITIALIZED);
	_state = STATE_INITIALIZED_NOT_VISIBLE;

    LOG("initialize");

    gdt_set_callback_touch(&on_touch);
}

void gdt_hook_visible(bool newSurface, int width, int height) {
	ASSERT(_state == STATE_INITIALIZED_NOT_VISIBLE);
	_state = STATE_INITIALIZED_VISIBLE_NOT_ACTIVE;

    LOG("visible, newSurface=%s, screen w=%d h=%d", newSurface? "true" : "false", width, height);

    if (newSurface) {
        GLuint program = linkProgram();

        _offsetUniform = glGetUniformLocation(program, "offset");
        GLuint positionAttrib = glGetAttribLocation(program, "position");

        static const GLfloat v[] = { 0, SIZE,
                                     0, 0,
                                     SIZE, SIZE,
                                     SIZE, 0    };
        GLuint vertexBuf;
        glGenBuffers(1, &vertexBuf);
        glBindBuffer(GL_ARRAY_BUFFER, vertexBuf);
        glBufferData(GL_ARRAY_BUFFER, sizeof(v), v, GL_STATIC_DRAW);

        static const GLubyte i[] = { 0, 1, 2, 3 };
        GLuint indexBuf;
        glGenBuffers(1, &indexBuf);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuf);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(i), i, GL_STATIC_DRAW);

        glEnableVertexAttribArray(positionAttrib);
        glVertexAttribPointer(positionAttrib, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);

        glUseProgram(program);

        glClearColor(0.4, 0.8, 0.4, 1);
    }

    _width = width;
    _height = height;
    glViewport(0, 0, _width, _height);
}

void gdt_hook_active() {
	ASSERT(_state == STATE_INITIALIZED_VISIBLE_NOT_ACTIVE);
	_state = STATE_INITIALIZED_VISIBLE_ACTIVE;

	LOG("active");
}

void gdt_hook_inactive() {
	ASSERT(_state == STATE_INITIALIZED_VISIBLE_ACTIVE);
	_state = STATE_INITIALIZED_VISIBLE_NOT_ACTIVE;

	LOG("inactive");
}

void gdt_hook_save_state() {
#ifdef GDT_PLATFORM_ANDROID
	ASSERT(_state == STATE_INITIALIZED_VISIBLE_NOT_ACTIVE);
#endif

#ifdef GDT_PLATFORM_IOS
	ASSERT(_state == STATE_INITIALIZED_NOT_VISIBLE);
#endif

	LOG("save_state");
}

void gdt_hook_hidden() {
    ASSERT(_state == STATE_INITIALIZED_VISIBLE_NOT_ACTIVE);
    _state = STATE_INITIALIZED_NOT_VISIBLE;


    LOG("hidden");
}

void gdt_hook_render() {
	ASSERT(_state == STATE_INITIALIZED_VISIBLE_NOT_ACTIVE || _state == STATE_INITIALIZED_VISIBLE_ACTIVE);

    glClear(GL_COLOR_BUFFER_BIT);

    glUniform2f(_offsetUniform, _x, _y);
    glDrawElements(GL_TRIANGLE_STRIP, 4, GL_UNSIGNED_BYTE, NULL); 
}

