using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyApp.Infrastructure.Data;

namespace StudyApp.Api.Controllers;

[ApiController]
[Route("api/v1/branding")]
[AllowAnonymous]
public sealed class BrandingController : ControllerBase
{
    private readonly ApplicationDbContext _context;

    public BrandingController(ApplicationDbContext context) => _context = context;

    [HttpGet("logo")]
    [ResponseCache(Duration = 86400, Location = ResponseCacheLocation.Any)]
    public async Task<IActionResult> GetLogo(CancellationToken cancellationToken)
    {
        var logo = await _context.AppBrandAssets
            .AsNoTracking()
            .FirstOrDefaultAsync(asset => asset.Key == "studyapp-logo", cancellationToken);

        if (logo == null)
        {
            return NotFound(new { message = "The StudyApp logo has not been seeded into the database." });
        }

        var accept = Request.Headers.Accept.ToString();
        if (accept.Contains("application/json", StringComparison.OrdinalIgnoreCase) &&
            !accept.Contains("image/svg+xml", StringComparison.OrdinalIgnoreCase) &&
            !accept.Contains("*/*", StringComparison.OrdinalIgnoreCase))
        {
            return Ok(new { key = logo.Key, contentType = logo.ContentType, content = logo.Content });
        }

        return Content(logo.Content, logo.ContentType ?? "image/svg+xml", System.Text.Encoding.UTF8);
    }
}
