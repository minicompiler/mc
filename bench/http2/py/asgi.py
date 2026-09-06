# A 10-line ASGI app, served by uvicorn (python3 -m uvicorn asgi:app --host 127.0.0.1 --port PORT).
async def app(scope, receive, send):
    if scope["type"] != "http":
        return
    await send({"type": "http.response.start", "status": 200,
                "headers": [(b"content-type", b"text/plain"), (b"content-length", b"13")]})
    await send({"type": "http.response.body", "body": b"hello, world\n"})
