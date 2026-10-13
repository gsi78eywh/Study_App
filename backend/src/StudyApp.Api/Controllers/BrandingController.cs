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
    [Produces("image/svg+xml")]
    public async Task<IActionResult> GetLogo(CancellationToken cancellationToken)
    {
        var logo = await _context.AppBrandAssets
            .AsNoTracking()
            .FirstOrDefaultAsync(asset => asset.Key == "studyapp-logo", cancellationToken);

        return logo == null
            ? NotFound(new { message = "The StudyApp logo has not been seeded into the database." })
            : Content(logo.Content, logo.ContentType, System.Text.Encoding.UTF8);
    }
}
