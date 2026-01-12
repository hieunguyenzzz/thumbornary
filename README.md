# Thumbornary

A self-hosted Cloudinary-compatible image CDN powered by Thumbor.

## Features

- **Cloudinary-compatible URLs** - Drop-in replacement for Cloudinary
- **Auto WebP** - Serves WebP to supporting browsers (39% smaller)
- **Multiple origins** - Route to different image sources
- **Aggressive caching** - Nginx + Thumbor result storage
- **Quality 90** - High quality output

## URL Format

```
https://thumbor.example.com/{transformations}/{origin}/{path}
```

### Example

```
https://thumbor.example.com/w_1024,c_limit,q_90/interior/cdn/shop/files/image.jpg
```

Fetches from: `https://interioricons.com/cdn/shop/files/image.jpg`

## Transformations

| Param | Description | Example |
|-------|-------------|---------|
| `w_1024` | Width | Resize to 1024px wide |
| `h_800` | Height | Resize to 800px tall |
| `c_limit` | Fit-in mode | Don't upscale, fit within bounds |
| `q_90` | Quality | JPEG quality (1-100) |

## Origins

| Prefix | Domain |
|--------|--------|
| `interior` | interioricons.com |
| `tina` | assets.tina.io |
| `anandjoeltina` | assets.tina.io/3a743d97-... |
| `mobelaris` | old.mobelaris.com |
| `shopify` | cdn.shopify.com |
| `wp-content` | merakiweddingplanner.com/wp-content |
| `uploads` | strapi.merakiweddingplanner.com/uploads |

## Quick Start

```bash
# Clone
git clone git@github.com:hieunguyenzzz/thumbornary.git
cd thumbornary

# Start
docker compose up -d

# Test
curl -I http://localhost:8180/w_500/interior/cdn/shop/files/test.jpg
```

## Architecture

```
Client Request
      ↓
   Nginx (port 8180)
   - Parse Cloudinary params
   - Detect Accept header (WebP)
   - Proxy cache (365 days)
      ↓
   Thumbor (port 8888)
   - Fetch from origin
   - Resize, compress
   - Result cache (forever)
      ↓
   Response (JPEG or WebP)
```

## Configuration

### thumbor.conf
- `QUALITY = 90` - Output quality
- `AUTO_WEBP = True` - Enable WebP
- `RESULT_STORAGE_EXPIRATION_SECONDS = 0` - Cache forever

### nginx.conf
- WebP auto-detection via Accept header
- Separate cache keys for JPEG/WebP
- 365-day proxy cache

## Performance

| Format | Size | vs Cloudinary |
|--------|------|---------------|
| Cloudinary q_auto | 42KB | baseline |
| Thumbor JPEG q90 | 60KB | +42% |
| **Thumbor WebP q90** | **36KB** | **-14%** |

## License

MIT
