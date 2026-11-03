#version 450

//   Pal shader - pass 3
//   by guest.r

layout(push_constant) uniform Push
{
   vec4 OutputSize;
   vec4 OriginalSize;
   vec4 SourceSize;
   uint FrameCount;
   float PAL_FILT;   
   float pal_scale;
   float pal_ring;
   float pal_res;
   float GCORR;
   float RFNOISE;
   float RFNOISE1;
} params;

layout(std140, set = 0, binding = 0) uniform UBO
{
	mat4 MVP;
} global;

#pragma parameter pal-row3    "-------------------------------------------------" 0.0 0.0 0.0 1.0
#pragma parameter GCORR       "          PAL Y Gamma Correct     " 1.15 1.0 2.6 0.05
#pragma parameter RFNOISE     "          PAL RF Luma Noise       " 0.00 0.0 0.5 0.01
#pragma parameter RFNOISE1    "          PAL RF Chroma Noise     " 0.00 0.0 0.5 0.01

#pragma parameter PAL_FILT    "          PAL Connection: RF | Composite | S-Video | SCART " 2.00 1.00 4.00 1.000
#pragma parameter pal_res     "          PAL Resolution: Connection/Core                  " 1.00 1.00 2.00 1.000
#pragma parameter pal_scale   "          PAL Resolution: Scaling                          " 1.00 0.20 2.50 0.025
#pragma parameter pal_ring    "          PAL Anti Ringing                                 " 0.50 0.00 1.00 0.050
#pragma parameter pal-row4    "-------------------------------------------------" 0.0 0.0 0.0 1.0

#define RFNOISE   params.RFNOISE
#define RFNOISE1  params.RFNOISE1
#define pal_scale params.pal_scale

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main()
{
   gl_Position = global.MVP * Position;
   vTexCoord = TexCoord + vec2(0.125 * params.OriginalSize.z, 0.0);
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

const mat3 yuv_rgb =

mat3 (1.00000,   0.00000,   1.13983,
      1.00000,  -0.39465,  -0.58060,
      1.00000,   2.03211,   0.00000);

vec3 yuv2rgb(vec3 yuv)
{
	return yuv * yuv_rgb;
}


vec2 psrnd(vec2 TexCoord, float FrameCount) {
    vec3 p = vec3(TexCoord * 16758.5453, FrameCount);
    float x = fract(sin(dot(p, vec3(12.9898, 78.233, 3.183))) * 43758.5453);
    float y = fract(sin(dot(p, vec3(25.9796, 14.113, 11.271))) * 96321.9124);
    return vec2(x, y);
}

vec3 Noise(vec2 TexCoord, float FrameCount) {
    TexCoord = psrnd(TexCoord, FrameCount);
    vec3 p = vec3(TexCoord * 758.5453, FrameCount);
    float res = fract(sin(dot(p, vec3(12.989835, 78.23341, 0.16453))) * 43758.54531);
    res = 2.0*abs(0.5-res);
    float lns = float(abs(0.75-res) < 0.1*RFNOISE );
    float cny = float(abs(0.25-res) < 0.4*RFNOISE1);
    float cnz = float(abs(0.50-res) < 0.4*RFNOISE1);		
	lns = lns*smoothstep(0.75-0.1*RFNOISE , 0.75+0.1*RFNOISE , res);
    cny = cny*smoothstep(0.25-0.4*RFNOISE1, 0.25+0.4*RFNOISE1, res);
    cnz = cnz*smoothstep(0.50-0.4*RFNOISE1, 0.50+0.4*RFNOISE1, res);	
	return vec3(min(lns,0.675), cny, cnz);
} 

vec3 sample_yuv(vec3 dx)
{
   return vec3(texture(Source, vTexCoord + dx.xz).x + texture(Source, vTexCoord - dx.xz).x, texture(Source, vTexCoord + dx.yz).yz + texture(Source, vTexCoord - dx.yz).yz);
}

float CON_TYPE[4] = float[4] (288.0, 320.0, 410.0, 512.0);

const int TAPS_PAL = 24;

// Y filter

float luma_weight_pal_25[25] = float[25](
  -0.016500,
  -0.020218,
  -0.025000,
  -0.029469,
  -0.033500,
  -0.035062,
  -0.038500,
  -0.047562,
  -0.062000,
  -0.084469,
  -0.110000,
  -0.141719,
  -0.158000,
  -0.144031,
  -0.082500,
   0.063469,
   0.250000,
   0.460156,
   0.650000,
   0.749375,
   0.820000,
   0.915000,
   0.990000,
   0.995000,
   1.000000
);


// UV chroma filter

const float chroma_weight_pal_25[25] = float[25](
  -0.001100,
  -0.001650,
  -0.002500,
  -0.003700,
  -0.005200,
  -0.006900,
  -0.008300,
  -0.009000,
  -0.008100,
  -0.005600,
  -0.002200,
   0.000300,
   0.002300,
   0.005200,
   0.009000,
   0.023600,
   0.049000,
   0.075200,
   0.152100,
   0.339700,
   0.447800,
   0.676000,
   0.892000,
   0.984000,
   1.000000
);


void main()
{
   float yres = CON_TYPE[int(params.PAL_FILT)-1];
   float hres = (params.pal_res < 1.5) ? yres : params.OriginalSize.x;
   float cres = yres / 320.0;
   
   float res = pal_scale;
   float one_x = 0.125 / hres / res;
   float one_y = 0.250 / hres / res / cres;
   
   vec3 signal = vec3(0.0);

   float offset = 0.0; int i = 0;
   vec3 wsum = 0.0.xxx;
   vec3 sums = wsum;
   vec3 tmp  = wsum;  

   vec3 dx = vec3(one_x, one_y, 0.0);
   float mit = 1.0;
   float iloop = 24.0;
   vec3 dx1 = dx;
	
   for (i = 0; i < 24; i++)
   {
      offset = float(i); dx1.xy = (offset - iloop)*dx.xy;
      sums = sample_yuv(dx1);
      tmp = vec3(luma_weight_pal_25[i], chroma_weight_pal_25[i].xx);
      wsum = wsum + tmp;
      signal += sums * tmp;
   }
   tmp = vec3(luma_weight_pal_25[TAPS_PAL], chroma_weight_pal_25[TAPS_PAL], chroma_weight_pal_25[TAPS_PAL]);
   wsum = wsum + wsum + tmp;
   signal += texture(Source, vTexCoord).xyz * tmp;
   signal = signal / wsum;

   if (params.pal_ring > 0.05)
   {
      vec2 dx = vec2(8.0 * one_x / min(res, 1.0), 0.0);
      float a = texture(Source, vTexCoord - 2.0*dx).a;
      float b = texture(Source, vTexCoord -     dx).a;
      float c = texture(Source, vTexCoord + 2.0*dx).a;
      float d = texture(Source, vTexCoord +     dx).a;
      float e = texture(Source, vTexCoord         ).a;	  
      signal.x = mix(signal.x, clamp(signal.x, min(min(min(a,b),min(c,d)),e), max(max(max(a,b),max(c,d)),e)), params.pal_ring);
   }

   signal.x = pow(max(signal.x, 0.0), 1.0/params.GCORR);

	// ADD RF Noise
   vec3 ns = Noise(vTexCoord, float(params.FrameCount));
   signal.x = mix(signal.x, ns.x, min(0.175 + 2.0*RFNOISE, 1.25)*ns.x);
   signal.yz*= (1.0-2.0*vec2(ns.y,ns.z));
   FragColor = vec4(clamp(yuv2rgb(signal), 0.0, 1.0), 1.0);
}  
