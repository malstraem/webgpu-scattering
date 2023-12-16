struct Uniforms {
  resolution: vec2f,
  time: f32
}

struct Ray {
  origin: vec3f,
  direction: vec3f
}

struct Earth {
  planet: vec4f,
  atmosphereThickness: f32
}

@group(0) @binding(0) var<uniform> uniforms : Uniforms;
@group(0) @binding(1) var texSampler: sampler;
@group(0) @binding(2) var dayTexture: texture_2d<f32>;
@group(0) @binding(3) var nightTexture: texture_2d<f32>;
@group(0) @binding(4) var cloudTexture: texture_2d<f32>;

const InScatterCount = 80;
const OutScatterCount = 8;
const PI = 3.14159265;

const SSAA = 8;

const earth = Earth(vec4(vec3(), 1), 0.15);

fn getRayDirection(fov: f32, size: vec2f, position: vec2f) -> vec3f
{
  let xy = position - (size * 0.5);

  let halfFovCotangent = tan(radians(90 - (fov * 0.5)));
  let z = size.y * 0.5 * halfFovCotangent;

  return normalize(vec3(xy, -z));
}

fn getRotation(angle: vec2f) -> mat3x3f
{
  let sin = sin(angle);
  let cos = cos(angle);

  return mat3x3f(cos.y, 0, -sin.y,
                 sin.y * sin.x, cos.x, cos.y * sin.x,
                 sin.y * cos.x, -sin.x, cos.y * cos.x);
}

fn getSphereIntersects(ray: Ray, radius: f32) -> vec2f
{
  let b = dot(ray.origin, ray.direction);
  let c = dot(ray.origin, ray.origin) - (radius * radius);

  var d = (b * b) - c;

  if (d < 0f)
  {
    return vec2(1e4f, -1e4f);
  }

  d = sqrt(d);

  return vec2(-b - d, -b + d);
}

fn density(point: vec3f, ph: f32) -> f32
{
  return exp(-max(length(point) - earth.planet.w, 0) / ph / earth.atmosphereThickness);
}

fn optic(point: vec3f, q: vec3f, ph: f32) -> f32
{
  let s = (q - point) / OutScatterCount;

  var v = point + (s * 0.5);

  var sum = 0f;

  for (var i = 0; i < OutScatterCount; i++)
  {
    sum += density(v, ph);
    v += s;
  }

  return sum * length(s);
}

fn rayPhase(cc: f32) -> f32
{
  return 3f / 16f / PI * (1f + cc);
}

fn miePhase(g: f32, c: f32, cc: f32) -> f32
{
  let gg = g * g;
  let a = (1f - gg) * (1f + cc);
  var b = 1f + gg - (2f * g * c);

  b *= sqrt(b) * (2f + gg);

  return 3f / 8f / PI * a / b;
}

fn getScattering(ray: Ray, intersects: vec2f, lightDirection: vec3f) -> vec3f
{
  let phRay = 0.05;
  let phMie = 0.02;
  let kMieEx = 1.1;

  let kRay = vec3(3.8, 13.5, 33);
  let kMie = vec3(21f);

  var sumRay = vec3f();
  var sumMie = vec3f();

  var nRay0 = 0f;
  var nMie0 = 0f;

  let len = (intersects.y - intersects.x) / InScatterCount;

  let s = ray.direction * len;
  var v = ray.origin + (ray.direction * (intersects.x + (len * 0.5)));

  for (var i = 0; i < InScatterCount; i++)
  {
    v += s;

    let dRay = density(v, phRay) * len;
    let dMie = density(v, phMie) * len;

    nRay0 += dRay;
    nMie0 += dMie;

    let stepRay = Ray(v, lightDirection);
    let stepIntersects = getSphereIntersects(stepRay, earth.planet.w + earth.atmosphereThickness);

    let u = v + (lightDirection * stepIntersects.y);

    let nRay1 = optic(v, u, phRay);
    let nMie1 = optic(v, u, phMie);

    let attenuate = exp((-(nRay0 + nRay1) * kRay) - ((nMie0 + nMie1) * kMie * kMieEx));

    sumRay += dRay * attenuate;
    sumMie += dMie * attenuate;
  }

  let c = dot(ray.direction, -lightDirection);
  let cc = c * c;

  let scattering = (sumRay * kRay * rayPhase(cc)) + (sumMie * kMie * miePhase(-0.8, c, cc));

  return 10 * scattering;
}

@fragment
fn main(@builtin(position) fragPosition : vec4f) -> @location(0) vec4f
{
  let fragcoord = fragPosition.xy;

  let eye = vec3f(0, 0, 3);

  let lightDirection = vec3f(0, 0, 1);

  let rayDirection = getRayDirection(45, uniforms.resolution, fragcoord);

  let planetRotation = getRotation(vec2(0, uniforms.time / 10));
  let cloudRotation = getRotation(vec2(0, uniforms.time / 5));
  let atmosphereRotation = getRotation(vec2(0.1, uniforms.time));

  var planetRay = Ray(planetRotation * eye, planetRotation * rayDirection);
  var cloudRay = Ray(cloudRotation * eye, cloudRotation * rayDirection);
  let atmosphereRay = Ray(eye * atmosphereRotation, rayDirection * atmosphereRotation);

  var planetIntersects = getSphereIntersects(planetRay, earth.planet.w);
  var atmosphereIntersects = getSphereIntersects(atmosphereRay, earth.planet.w + earth.atmosphereThickness);

  atmosphereIntersects.y = min(atmosphereIntersects.y, planetIntersects.x);

  let scattering = getScattering(atmosphereRay, atmosphereIntersects, lightDirection);

  var planet = vec3f();

  for (var m = -SSAA / 2; m < SSAA / 2; m++)
  {
      for (var n = -SSAA / 2; n < SSAA / 2; n++)
      {
          let aaOffset = vec2(f32(m), f32(n)) / SSAA;

          let planetRayDirection = getRayDirection(45, uniforms.resolution, fragcoord + aaOffset);

          planetRay.direction = planetRotation * planetRayDirection;

          planetIntersects = getSphereIntersects(planetRay, earth.planet.w);

          if (planetIntersects.x <= planetIntersects.y)
          {
            let position = planetRay.origin + (planetRay.direction * planetIntersects.x);

            let cloudPosition = position / uniforms.time;

            let latitude = 90 - (acos(position.y / length(position)) * 180 / PI);
            let longitude = atan2(position.x, position.z) * 180 / PI;

            var uv = vec2(longitude / 360, latitude / 180) + 0.5;

            let latitude2 = 90 - (acos(cloudPosition.y / length(cloudPosition)) * 180 / PI);
            let longitude2 = atan2(cloudPosition.x, cloudPosition.z) * 180 / PI;

            var uv2 = vec2(longitude2 / 360, latitude2 / 180) + 0.5;

            let light = dot(normalize(atmosphereRay.origin + (atmosphereRay.direction * planetIntersects.x)), lightDirection);

            let cloud = textureSampleBaseClampToEdge(cloudTexture, texSampler, uv2).rgb;

            var day = mix(textureSampleBaseClampToEdge(dayTexture, texSampler, uv).rgb, scattering, 0.6);
            day += cloud;
            day *= light;

            //var dayColor = textureSampleBaseClampToEdge(dayTexture, texSampler, uv).rgb * light;

            //dayColor = mix(dayColor, cloudColor, smoothstep(-earth.atmosphereThickness, earth.atmosphereThickness, light));

            var night = pow(textureSampleBaseClampToEdge(nightTexture, texSampler, uv).rgb, vec3(1.8));
            night += cloud / 32;

            planet += mix(night, day, smoothstep(-earth.atmosphereThickness, earth.atmosphereThickness, light));
          }
      }
  }

  planet /= SSAA * SSAA;

  return vec4(planet + scattering, 1);
}
