/*
 * Weston module that shares the nested Weston's clipboard with Windows.
 *
 * Waydroid's Android keeps its clipboard in the Wayland selection of the
 * compositor it runs in. The nested Weston never forwards that selection to
 * WSLg, so copy and paste stopped at the window's edge. This module watches
 * the selection and talks to a helper process (windows-clipboard.py) over
 * its stdin/stdout, one line per change: "set <base64 UTF-8 text>".
 *
 *   Android copies    -> selection changes -> line to the helper -> Windows
 *   Windows copies    -> line from the helper -> our selection -> Android
 *
 * Loaded with: weston --modules=/path/clipboard-bridge.so
 * The helper command comes from $ANDROID_WSL_CLIPBOARD_HELPER (run by sh).
 */
#define _GNU_SOURCE  /* pipe2 */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <libweston/libweston.h>

#define container_of(ptr, type, member) \
	((type *)((char *)(ptr) - offsetof(type, member)))

#define MAX_TEXT (4 * 1024 * 1024)

static const char *const TEXT_TYPES[] = {
	"text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "TEXT", "STRING",
};
#define N_TEXT_TYPES (sizeof TEXT_TYPES / sizeof TEXT_TYPES[0])

struct bridge {
	struct weston_compositor *compositor;
	struct weston_seat *seat;
	struct wl_listener seat_created;
	struct wl_listener selection;
	int to_helper;
	struct wl_event_source *from_helper;
	char *line;
	size_t line_len;
};

/* A read of the current selection, started when it changes. */
struct reader {
	struct bridge *bridge;
	struct wl_event_source *source;
	char *data;
	size_t len;
};

/* Text set from Windows, offered to Android. */
struct text_source {
	struct weston_data_source base;
	char *text;
	size_t len;
	int refs;
};

/* An Android read of our text, written as the pipe allows. */
struct writer {
	struct text_source *source;
	struct wl_event_source *event;
	size_t offset;
};

/* --- base64 --------------------------------------------------------------- */

static const char B64[] =
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static char *
b64_encode(const char *in, size_t len)
{
	char *out = malloc(4 * ((len + 2) / 3) + 1), *p = out;
	size_t i;

	if (!out)
		return NULL;
	for (i = 0; i + 2 < len; i += 3) {
		uint32_t v = (uint8_t)in[i] << 16 | (uint8_t)in[i + 1] << 8 | (uint8_t)in[i + 2];
		*p++ = B64[v >> 18]; *p++ = B64[v >> 12 & 63];
		*p++ = B64[v >> 6 & 63]; *p++ = B64[v & 63];
	}
	if (i < len) {
		uint32_t v = (uint8_t)in[i] << 16 | (i + 1 < len ? (uint8_t)in[i + 1] << 8 : 0);
		*p++ = B64[v >> 18]; *p++ = B64[v >> 12 & 63];
		*p++ = i + 1 < len ? B64[v >> 6 & 63] : '=';
		*p++ = '=';
	}
	*p = '\0';
	return out;
}

static char *
b64_decode(const char *in, size_t *len)
{
	char *out = malloc(strlen(in) / 4 * 3 + 3);
	uint32_t v = 0;
	int bits = 0;

	if (!out)
		return NULL;
	*len = 0;
	for (; *in && *in != '='; in++) {
		const char *c = strchr(B64, *in);
		if (!c)
			continue;
		v = v << 6 | (uint32_t)(c - B64);
		bits += 6;
		if (bits >= 8) {
			bits -= 8;
			out[(*len)++] = (char)(v >> bits & 0xff);
		}
	}
	return out;
}

/* --- Android -> Windows ----------------------------------------------------- */

static void
send_to_helper(struct bridge *b, const char *text, size_t len)
{
	char *enc;
	size_t n;

	if (b->to_helper < 0 || !(enc = b64_encode(text, len)))
		return;
	weston_log("clipboard-bridge: Android -> Windows (%zu bytes)\n", len);
	n = strlen(enc);
	if (dprintf(b->to_helper, "set %s\n", enc) != (int)n + 5) {
		weston_log("clipboard-bridge: helper is gone (%s)\n", strerror(errno));
		close(b->to_helper);
		b->to_helper = -1;
	}
	free(enc);
}

static int
reader_data(int fd, uint32_t mask, void *data)
{
	struct reader *r = data;
	char buf[4096];
	ssize_t n = read(fd, buf, sizeof buf);

	if (n > 0 && r->len + (size_t)n <= MAX_TEXT) {
		char *grown = realloc(r->data, r->len + (size_t)n);
		if (grown) {
			memcpy(grown + r->len, buf, (size_t)n);
			r->data = grown;
			r->len += (size_t)n;
			return 1;
		}
	}
	if (n < 0 && errno == EAGAIN)
		return 1;
	if (n == 0 && r->len > 0)
		send_to_helper(r->bridge, r->data, r->len);
	wl_event_source_remove(r->source);
	close(fd);
	free(r->data);
	free(r);
	return 1;
}

static void text_source_send(struct weston_data_source *, const char *, int32_t);

static void
selection_changed(struct wl_listener *listener, void *data)
{
	struct bridge *b = container_of(listener, struct bridge, selection);
	struct weston_seat *seat = data;
	struct weston_data_source *source = seat->selection_data_source;
	struct wl_event_loop *loop;
	const char *type = NULL, **offered;
	struct reader *r;
	size_t i, j;
	int p[2];

	/* Only copies made by a client (Android). Sources without one are ours
	 * (text from Windows) or Weston's own clipboard restoring a selection
	 * whose client let go of it: text we've already seen. */
	if (!source || !source->resource)
		return;

	offered = source->mime_types.data;
	for (i = 0; i < N_TEXT_TYPES && !type; i++)
		for (j = 0; j < source->mime_types.size / sizeof *offered; j++)
			if (strcmp(offered[j], TEXT_TYPES[i]) == 0)
				type = TEXT_TYPES[i];
	if (!type || pipe2(p, O_CLOEXEC | O_NONBLOCK) < 0)
		return;

	r = calloc(1, sizeof *r);
	if (!r) {
		close(p[0]);
		close(p[1]);
		return;
	}
	r->bridge = b;
	loop = wl_display_get_event_loop(b->compositor->wl_display);
	r->source = wl_event_loop_add_fd(loop, p[0], WL_EVENT_READABLE, reader_data, r);
	/* The source owns p[1] from here: it hands it to the copying client. */
	source->send(source, type, p[1]);
}

/* --- Windows -> Android ----------------------------------------------------- */

static void
text_source_unref(struct text_source *s)
{
	if (--s->refs > 0)
		return;
	wl_signal_emit(&s->base.destroy_signal, &s->base);
	wl_array_release(&s->base.mime_types);
	free(s->text);
	free(s);
}

static int
writer_data(int fd, uint32_t mask, void *data)
{
	struct writer *w = data;
	ssize_t n = write(fd, w->source->text + w->offset, w->source->len - w->offset);

	if (n > 0)
		w->offset += (size_t)n;
	if (w->offset == w->source->len || (n < 0 && errno != EAGAIN)) {
		wl_event_source_remove(w->event);
		close(fd);
		text_source_unref(w->source);
		free(w);
	}
	return 1;
}

static void
text_source_send(struct weston_data_source *base, const char *mime_type, int32_t fd)
{
	struct text_source *s = container_of(base, struct text_source, base);
	struct wl_event_loop *loop =
		wl_display_get_event_loop(s->base.seat->compositor->wl_display);
	struct writer *w = calloc(1, sizeof *w);

	if (!w) {
		close(fd);
		return;
	}
	fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
	w->source = s;
	s->refs++;
	w->event = wl_event_loop_add_fd(loop, fd, WL_EVENT_WRITABLE, writer_data, w);
}

static void
text_source_accept(struct weston_data_source *base, uint32_t serial, const char *mime_type)
{
}

static void
text_source_release(void *data)
{
	text_source_unref(data);
}

static void
text_source_cancel(struct weston_data_source *base)
{
	struct text_source *s = container_of(base, struct text_source, base);

	/* Replaced by a newer selection. Weston calls this before it stops
	 * listening for the source's destruction, so destroying it right away
	 * would look like the selection was cleared (and Weston would restore
	 * the previous one). Release it on the next loop turn instead. */
	wl_event_loop_add_idle(wl_display_get_event_loop(s->base.seat->compositor->wl_display),
			       text_source_release, s);
}

static void
set_selection(struct bridge *b, char *text, size_t len)
{
	struct text_source *s;
	size_t i;

	if (!b->seat || !(s = calloc(1, sizeof *s))) {
		free(text);
		return;
	}
	s->text = text;
	s->len = len;
	s->refs = 1;
	s->base.seat = b->seat;
	s->base.send = text_source_send;
	s->base.accept = text_source_accept;
	s->base.cancel = text_source_cancel;
	wl_signal_init(&s->base.destroy_signal);
	wl_array_init(&s->base.mime_types);
	for (i = 0; i < N_TEXT_TYPES; i++) {
		const char **slot = wl_array_add(&s->base.mime_types, sizeof *slot);
		if (slot)
			*slot = TEXT_TYPES[i];
	}
	weston_seat_set_selection(b->seat, &s->base,
				  wl_display_next_serial(b->compositor->wl_display));
	/* Weston ignores a selection whose serial is older than the current
	 * one's. Android copies with the serial of its last keyboard focus,
	 * older than ours, so forget ours or Android's next copy is lost. */
	b->seat->selection_serial = 0;
}

static void
handle_line(struct bridge *b, const char *line)
{
	size_t len;
	char *text;

	if (strncmp(line, "set ", 4) != 0 || !(text = b64_decode(line + 4, &len)))
		return;
	weston_log("clipboard-bridge: Windows -> Android (%zu bytes)\n", len);
	set_selection(b, text, len);
}

static int
helper_data(int fd, uint32_t mask, void *data)
{
	struct bridge *b = data;
	char buf[4096];
	ssize_t n = read(fd, buf, sizeof buf);
	size_t start = 0, i;

	if (n <= 0) {
		if (n < 0 && errno == EAGAIN)
			return 1;
		weston_log("clipboard-bridge: helper exited\n");
		wl_event_source_remove(b->from_helper);
		b->from_helper = NULL;
		close(fd);
		return 1;
	}
	for (i = 0; i < (size_t)n; i++) {
		if (buf[i] != '\n')
			continue;
		b->line = realloc(b->line, b->line_len + i - start + 1);
		memcpy(b->line + b->line_len, buf + start, i - start);
		b->line[b->line_len + i - start] = '\0';
		handle_line(b, b->line);
		b->line_len = 0;
		start = i + 1;
	}
	if (start < (size_t)n && b->line_len + (size_t)n - start < 2 * MAX_TEXT) {
		b->line = realloc(b->line, b->line_len + (size_t)n - start);
		memcpy(b->line + b->line_len, buf + start, (size_t)n - start);
		b->line_len += (size_t)n - start;
	}
	return 1;
}

/* --- setup ------------------------------------------------------------------ */

static void
attach_seat(struct bridge *b, struct weston_seat *seat)
{
	if (b->seat)
		return;
	b->seat = seat;
	wl_signal_add(&seat->selection_signal, &b->selection);
}

static void
seat_created(struct wl_listener *listener, void *data)
{
	attach_seat(container_of(listener, struct bridge, seat_created), data);
}

static int
spawn_helper(struct bridge *b, const char *command)
{
	int in[2], out[2];
	pid_t pid;

	if (pipe2(in, O_CLOEXEC) < 0 || pipe2(out, O_CLOEXEC) < 0)
		return -1;
	pid = fork();
	if (pid < 0)
		return -1;
	if (pid == 0) {
		dup2(in[0], STDIN_FILENO);
		dup2(out[1], STDOUT_FILENO);
		execl("/bin/sh", "sh", "-c", command, (char *)NULL);
		_exit(127);
	}
	close(in[0]);
	close(out[1]);
	b->to_helper = in[1];
	fcntl(out[0], F_SETFL, O_NONBLOCK);
	b->from_helper = wl_event_loop_add_fd(
		wl_display_get_event_loop(b->compositor->wl_display),
		out[0], WL_EVENT_READABLE, helper_data, b);
	return 0;
}

WL_EXPORT int
wet_module_init(struct weston_compositor *compositor, int *argc, char *argv[])
{
	const char *command = getenv("ANDROID_WSL_CLIPBOARD_HELPER");
	struct weston_seat *seat;
	struct bridge *b;

	if (!command || !*command) {
		weston_log("clipboard-bridge: ANDROID_WSL_CLIPBOARD_HELPER is not set\n");
		return 0;
	}
	b = calloc(1, sizeof *b);
	if (!b)
		return -1;
	b->compositor = compositor;
	b->to_helper = -1;
	b->selection.notify = selection_changed;
	b->seat_created.notify = seat_created;
	/* A helper that dies must not take the compositor with it. */
	signal(SIGPIPE, SIG_IGN);
	if (spawn_helper(b, command) < 0) {
		weston_log("clipboard-bridge: could not start the helper\n");
		free(b);
		return 0;
	}
	wl_list_for_each(seat, &compositor->seat_list, link)
		attach_seat(b, seat);
	wl_signal_add(&compositor->seat_created_signal, &b->seat_created);
	weston_log("clipboard-bridge: sharing the clipboard with Windows\n");
	return 0;
}
