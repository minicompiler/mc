// ASP.NET Core minimal API on Kestrel. Thread pool + async I/O, keep-alive on.
var builder = WebApplication.CreateSlimBuilder(args);
builder.Logging.ClearProviders();
var app = builder.Build();
app.MapGet("/", (HttpContext ctx) =>
{
    ctx.Response.ContentType = "text/plain";
    ctx.Response.ContentLength = 13;
    return ctx.Response.Body.WriteAsync("hello, world\n"u8.ToArray()).AsTask();
});
app.Run("http://127.0.0.1:" + args[0]);
