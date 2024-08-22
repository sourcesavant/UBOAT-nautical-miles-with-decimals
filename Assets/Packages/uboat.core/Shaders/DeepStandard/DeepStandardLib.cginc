#ifndef DEEP_STANDARD_INCLUDED
#define DEEP_STANDARD_INCLUDED

#include "UnityCG.cginc"
#include "Packages/PlayWay Water/Shaders/Includes/EarthCurvature.cginc"

half _FogMaxValue;
half _SnowCover;

#if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
    #if (SHADER_TARGET < 30) || defined(SHADER_API_MOBILE)
        // mobile or SM2.0: fog factor was already calculated per-vertex, so just lerp the color
        #define DEEP_APPLY_FOG_COLOR(coord,col,fogCol) UNITY_FOG_LERP_COLOR(col,fogCol,(coord).x)
    #else
        // SM3.0 and PC/console: calculate fog factor and lerp fog color
		#if !defined(PARTICLE_SHADER)
			#define DEEP_APPLY_FOG_COLOR(coord,col,fogCol) float unityFogFactor = unity_FogParams.x * (dist); unityFogFactor = exp2(-unityFogFactor*unityFogFactor); unityFogFactor = lerp(1.0, unityFogFactor, _FogMaxValue); UNITY_FOG_LERP_COLOR(col,fogCol,unityFogFactor)
		#else
			#define DEEP_APPLY_FOG_COLOR(coord,col,fogCol) float unityFogFactor = unity_FogParams.x * (UNITY_Z_0_FAR_FROM_CLIPSPACE(coord) * _ParticleFogFactor); unityFogFactor = exp2(-unityFogFactor*unityFogFactor); unityFogFactor = lerp(1.0, unityFogFactor, _FogMaxValue); UNITY_FOG_LERP_COLOR(col,fogCol,unityFogFactor)
		#endif
    #endif
#else
    #define DEEP_APPLY_FOG_COLOR(coord,col,fogCol)
#endif

#ifdef UNITY_PASS_FORWARDADD
    #define DEEP_APPLY_FOG(coord,col) DEEP_APPLY_FOG_COLOR(coord,col,fixed4(0,0,0,0))
#else
    #define DEEP_APPLY_FOG(coord,col) DEEP_APPLY_FOG_COLOR(coord,col,unity_FogColor)
#endif

#if defined(_DISSOLVE)
	#define DISSOLVE_MASK(x) DissolveMask(x)

	sampler2D _DissolveMask;
#else
	#define DISSOLVE_MASK(x) 
#endif

#if defined(_SIMPLE_WATER)
	half _PerlinIntensity;
	float _ClipHeight;
#endif

void DissolveMask(half2 uv)
{
#if defined(_DISSOLVE)
	half mask = tex2D(_DissolveMask, uv * _DissolveMaskScale);
	clip(mask - (1.0 - _DissolveThreshold));
#endif
}

	#if defined(USING_STEREO_MATRICES)
		// there is no support for stereo in our pipeline, these arrays are not being set
		float4x4 _StereoNonJitteredVP[2];
		float4x4 _StereoPreviousVP[2];
	#else
		float4x4 _NonJitteredViewProjMatrix;
		float4x4 _PrevViewProjMatrix;
	#endif

	#define _HasLastPositionData unity_MotionVectorsParams.x > 0
	#define _ForceNoMotion unity_MotionVectorsParams.y
	#define _MotionVectorDepthBias unity_MotionVectorsParams.z


struct MotionVectorData
{
	UNITY_POSITION(pos);
	float4 transferPos : TEXCOORD0;
	float4 transferPosOld : TEXCOORD1;
#if defined(_ALPHATEST_ON)
	float2 tex : TEXCOORD3;
#endif
#if defined(_DISSOLVE)
	float2 dissolveUV : TEXCOORD3;
#endif
	UNITY_VERTEX_OUTPUT_STEREO
};

struct MotionVertexInput
{
	float4 vertex : POSITION;
	float3 oldPos : TEXCOORD4;
	float2 uv0 : TEXCOORD0;
	float2 uv1 : TEXCOORD1;
#if defined(_TREE_MANUFACTURE)
	half3 normal    : NORMAL;
	fixed4 color    : COLOR0;
#elif defined(_HAIR)
	half3 normal    : NORMAL;
#endif
#if defined(_FLAG)
	uint id : SV_VertexID;
#endif
	UNITY_VERTEX_INPUT_INSTANCE_ID
};

#if defined(_TREE) || defined(_BILLBOARD)
	#include "DeepTreeLib.cginc"
#elif defined(_TREE_MANUFACTURE)
	#include "DeepTreeLibManufacture.cginc"
#else
	#define ApplyTreeEffects(a, b, c, d, e) 
#endif

half _CameraIndex;

MotionVectorData VertMotionVectors(MotionVertexInput v)
{
	MotionVectorData o;
	UNITY_SETUP_INSTANCE_ID(v);
	UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

	bool hasLastPositionData = _HasLastPositionData;

#if defined(_FLAG)
	float frameIndex = (_Time.y * _FlagAnimationSpeed) % _FlagAnimationFrameCount;
	int frameIndexLB = floor(frameIndex);
	int frameIndexUB = ceil(frameIndex);

	if(frameIndexUB == _FlagAnimationFrameCount)
		frameIndexUB = 0;

	float lerpFactor = frameIndex - frameIndexLB;
	int vertexID = v.id;

	int vbIndexLB = frameIndexLB * _FlagAnimationVertexCount + vertexID;
	int vbIndexUB = frameIndexUB * _FlagAnimationVertexCount + vertexID;

	v.vertex.xyz = lerp(_FlagAnimation[vbIndexLB].Position.xyz, _FlagAnimation[vbIndexUB].Position.xyz, lerpFactor);

	float previousTime = _Time.y - unity_DeltaTime.x;
	float previousFrameIndex = (previousTime * _FlagAnimationSpeed) % _FlagAnimationFrameCount;
	int previousFrameIndexLB = floor(previousFrameIndex);
	int previousFrameIndexUB = ceil(previousFrameIndex);

	if(previousFrameIndexUB == _FlagAnimationFrameCount)
		previousFrameIndexUB = 0;

	float previousLerpFactor = previousFrameIndex - previousFrameIndexLB;

	int previousVbIndexLB = previousFrameIndexLB * _FlagAnimationVertexCount + vertexID;
	int previousVbIndexUB = previousFrameIndexUB * _FlagAnimationVertexCount + vertexID;

	v.oldPos = lerp(_FlagAnimation[previousVbIndexLB].Position.xyz, _FlagAnimation[previousVbIndexUB].Position.xyz, previousLerpFactor);
	hasLastPositionData = 1;
#endif

	float4 posWorld = mul(unity_ObjectToWorld, v.vertex);

#if defined(USE_CUSTOM_AMBIENT)
	posWorld = CompensateForEarthCurvature(posWorld);
#endif

#if defined(_SIMPLE_WATER)
	v.vertex.y -= max(0.0, posWorld.y - _ClipHeight);
#endif

#if defined(_TREE_LEAVES_MANUFACTURE) || defined(_TREE_BARK_MANUFACTURE)
    CalculateWindMV(v);
#endif

#if defined(_HAIR)
	float3 normalWorld = UnityObjectToWorldNormal(v.normal);
	posWorld.xyz += normalWorld * _HairOffset;
#endif

	o.pos = mul(UNITY_MATRIX_VP, posWorld);

	// this works around an issue with dynamic batching
	// potentially remove in 5.4 when we use instancing
/*#if defined(UNITY_REVERSED_Z)
	o.pos.z -= _MotionVectorDepthBias * o.pos.w;
#else
	o.pos.z += _MotionVectorDepthBias * o.pos.w;
#endif*/

#if defined(_ALPHATEST_ON)
	o.tex = TRANSFORM_TEX(v.uv0, _MainTex);
#endif

#if defined(_DISSOLVE)
	o.dissolveUV = TRANSFORM_TEX(((_UVSec == 0) ? v.uv0 : v.uv1), _DetailAlbedoMap);
#endif

	float3 delta = v.vertex.xyz - v.oldPos;

	if (_CameraIndex == 1)
	{
	#if defined(USING_STEREO_MATRICES)
		o.transferPos = mul(_StereoNonJitteredVP[unity_StereoEyeIndex], CompensateForEarthCurvature(mul(unity_ObjectToWorld, v.vertex)));
		o.transferPosOld = mul(_StereoPreviousVP[unity_StereoEyeIndex], CompensateForEarthCurvature(mul(unity_MatrixPreviousM, hasLastPositionData && dot(delta, delta) < 0.2 ? float4(v.oldPos, 1) : v.vertex)));
	#else
		o.transferPos = mul(_NonJitteredViewProjMatrix, CompensateForEarthCurvature(mul(unity_ObjectToWorld, v.vertex)));
		o.transferPosOld = mul(_PrevViewProjMatrix, CompensateForEarthCurvature(mul(unity_MatrixPreviousM, hasLastPositionData && dot(delta, delta) < 0.2 ? float4(v.oldPos, 1) : v.vertex)));
	#endif
	}
	else
	{
	#if defined(USING_STEREO_MATRICES)
		o.transferPos = mul(_StereoNonJitteredVP[unity_StereoEyeIndex], mul(unity_ObjectToWorld, v.vertex));
		o.transferPosOld = mul(_StereoPreviousVP[unity_StereoEyeIndex], mul(unity_MatrixPreviousM, hasLastPositionData && dot(delta, delta) < 0.2 ? float4(v.oldPos, 1) : v.vertex));
	#else
		o.transferPos = mul(_NonJitteredViewProjMatrix, mul(unity_ObjectToWorld, v.vertex));
		o.transferPosOld = mul(_PrevViewProjMatrix, mul(unity_MatrixPreviousM, hasLastPositionData && dot(delta, delta) < 0.2 ? float4(v.oldPos, 1) : v.vertex));
	#endif
	}

	return o;
}

half4 FragMotionVectors(MotionVectorData i) : SV_Target
{
#if defined(_DISSOLVE)
	DISSOLVE_MASK(i.dissolveUV.xy);
#endif

#if defined(_ALPHATEST_ON)
	half alpha = tex2D(_MainTex, i.tex).a * _Color.a;
	clip(alpha - _Cutoff);
#endif

	float3 hPos = (i.transferPos.xyz / i.transferPos.w);
	float3 hPosOld = (i.transferPosOld.xyz / i.transferPosOld.w);

	// V is the viewport position at this pixel in the range 0 to 1.
	float2 vPos = (hPos.xy + 1.0f) / 2.0f;
	float2 vPosOld = (hPosOld.xy + 1.0f) / 2.0f;

#if UNITY_UV_STARTS_AT_TOP
	vPos.y = 1.0 - vPos.y;
	vPosOld.y = 1.0 - vPosOld.y;
#endif
	half2 uvDiff = vPos - vPosOld;

//#if defined(_DEEP_PIPELINE)
	return lerp(0, half4(uvDiff, 0, 1), (half)_ForceNoMotion);		// in SRP 0 means no motion instead of 1
//#else
//	return lerp(half4(uvDiff, 0, 1), 0, (half)_ForceNoMotion);
//#endif
}

#if defined(_DAMAGE_MAP)
sampler2D _DamageMask;
sampler2D _DamageMap;

void ApplyDamage(float2 uv0, float2 uv2, inout FragmentCommonData s)
{
	half damageMask = tex2D(_DamageMask, uv0);
	half surfaceCondition = min(1.0, damageMask * 0.025 + tex2D(_DamageMap, uv2));
	clip(surfaceCondition - 0.02);

	s.diffColor *= (0.02 + surfaceCondition * 0.98);
	s.specColor *= surfaceCondition;
	s.smoothness *= surfaceCondition;
}
#else
#define ApplyDamage(a, b, c) 
#endif

#if defined(_WETNESS_SUPPORT_ON)

half ApplyWetnessPre(float2 uv2)
{
	half wetness = min(1.0, dot(_WetnessBiasScale.xyz * tex2D(_WetnessMap, uv2).rgb + _WetnessBiasScale.www, 1));
	
	_BumpScale *= 1.0 - wetness * 0.55;
	_DetailNormalMapScale *= 1.0 - wetness;

	return wetness;
}

void ApplyWetness(float2 uv2, half wetness, inout FragmentCommonData s)
{
	s.diffColor *= 0.55 + 0.45 * max(1.0 - wetness, 1.0 - s.specColor.g * 3.0);
	s.smoothness = lerp(s.smoothness, 0.97, wetness);
}
#else
#define ApplyWetnessPre(a) 0
#define ApplyWetness(a, b, c)
#endif

#if defined(LIGHTHOUSE_WINDOWS)
float4 _GameTime;

void ApplyLighthouseEffect(inout half3 emissiveColor, float2 uv2)
{
	float2 hDeltas = frac(abs(-(_RotationOffset.xx / 360.0 + float2(0.5, 0.5) + _GameTime.xx * (75.0 / 360.0)) - uv2.xx));
	hDeltas = min(hDeltas, 1.0 - hDeltas);

	float2 deltaFromLight = float2(min(hDeltas.x, hDeltas.y), 0.5f - uv2.y);
	emissiveColor *= 0.0016 + 0.9984 * pow(1.0 - min(1.0, length(deltaFromLight * float2(1.0, 0.125)) / 0.17), 4.0);
}
#else
	#define ApplyLighthouseEffect(a, b)
#endif

#if defined (_MEGATEX)

sampler2D   _MegatexAlbedoMap;
sampler2D   _MegatexMetallicGlossMap;

#include "Packages/com.uboat.assemblies/DeepRenderPipeline/Utility/NoiseLib.cginc"

void ApplyMegatex(inout FragmentCommonData s, inout half occlusion, float4 uv, float3 worldPos)
{
	half distance = length(_WorldSpaceCameraPos - worldPos);

	float unused;
	float3 unused2;
	//s.diffColor = lerp(s.diffColor, DiffuseAndSpecularFromMetallic(_Color.rgb * tex2D(_MainTex, uv.xy * 0.2), 0.0, unused2, unused), saturate((distance - 5) / _PatternRepeatDistance) * 0.6);
	//s.diffColor = _Color.rgb * tex2D(_MainTex, uv.xy).rgb * (half3(1,1,1) - s.specColor);

	s.diffColor = lerp(s.diffColor, DiffuseAndSpecularFromMetallic(_Color.rgb * tex2D(_MainTex, uv.xy * 0.2).rgb, MetallicGloss(uv * 0.2), unused2, unused), saturate((distance - 5) / _PatternRepeatDistance) * 0.6);
	s.diffColor *= lerp(1.0, tex2D(_MegatexAlbedoMap, uv.zw) * unity_ColorSpaceDouble.rgb, _MegatexIntensity);

	float4 mos = tex2D(_MegatexMetallicGlossMap, uv.zw);
	s.specColor *= 1.0 - (1.0 - s.specColor) * (1.0 - mos.r);

	if (s.smoothness < 0.5)
		s.smoothness = lerp(0.0, mos.a, s.smoothness * 2.0f);
	else
		s.smoothness = lerp(mos.a, 1.0, (s.smoothness - 0.5f) * 2.0f);

	//s.smoothness *= mos.a;
	s.oneMinusReflectivity = 1.0 - s.smoothness;
	occlusion *= mos.g;

	half noiseIntensity = (1.0 - exp(distance * -_NoiseDistanceFactor)) * _NoiseIntensity;

	float freq = _NoiseFrequency;
	float noise = 0.0;
	for (int i = 0; i < 2; ++i)
	{
		noise += Perlin2D(float2(worldPos.x, worldPos.y + worldPos.z) * freq) * noiseIntensity;
		freq *= 2.0;
		noiseIntensity *= 0.6;
	}

	if (noise < 0.0)
		s.diffColor *= 1.0 / (1.0 - noise);
	else
		s.diffColor *= 1.0 + noise;
}
#else
	#define ApplyMegatex(s, occlusion, uv2, worldPos)
#endif

#if defined(_SNOW_SUPPORT_ON)
#define ApplySnowEffectsPre(vertexNormal) half snowFactor = saturate((vertexNormal.y - 0.5) * 8.0); \
	snowFactor *= _SnowCover;																		\
	_BumpScale *= 1.0 - snowFactor;

#define ApplySnowEffects(s, occlusion, uv) ApplySnowEffectsFunc(s, occlusion, uv, snowFactor)

void ApplySnowEffectsFunc(inout FragmentCommonData s, inout float occlusion, float2 uv, half snowFactor)
{
//#if defined(USE_CUSTOM_AMBIENT)
    half4 snowData = tex2D(_SnowAlbedo, uv);
    s.diffColor.rgb = lerp(s.diffColor.rgb, snowData.rgb, snowFactor);
    s.specColor.rgb = lerp(s.specColor.rgb, half3(0.1686, 0.1686, 0.1686), snowFactor);
    s.oneMinusReflectivity = lerp(s.oneMinusReflectivity, 0.9, snowFactor);
    s.smoothness = lerp(s.smoothness, snowData.a, snowFactor);
	occlusion = lerp(occlusion, 1.0, snowFactor);
//#endif
}

/*void ApplySnowEffects(inout FragmentCommonData s)
{
	float _SnowMultiplier = 1.0;		// move to parameter?
	float _NormalInfluence = 0.7;		// move to parameter?
	float _Snow = 1.0;		// move to parameter?

	float _Lux_SnowAmount2 = 0.5;
	float3 _Lux_SnowColor2 = float3(0.9, 0.9, 0.9);
	float4 _Lux_SnowSpecColor2 = float4(0.3, 0.3, 0.3, 0.15);

	half2 normalInfluence = lerp(half2(1,1), half2(s.normalWorld.y, -s.normalWorld.y) / * saturate(s.normalWorld.y + 1) * /, _NormalInfluence.xx);
	half baseSnowAmount = saturate(_Lux_SnowAmount2 * _SnowMultiplier / * 1.75 * / ) * s.alpha;
	half2 snow = saturate(baseSnowAmount.xx - saturate(half2(1,1) - normalInfluence - baseSnowAmount.xx * 0.25));
	//snow *= trngls.r;
	//BlendValue = saturate ( (CrrentBlendStrength - ( 1.0 - Mask)) / _Sharpness );
	snow = saturate( (snow / *- trngls.rr* /) * _Snow.xx ); // / 20 );
//  Sharpen snow
	//snow = saturate(snow * 1.0 * (2.0 - _Lux_SnowAmount2));
	//snow = smoothstep(0.5, 1, snow);
	s.diffColor = lerp( s.diffColor, _Lux_SnowColor2.xyz, snow.xxx);
//	We need snow on backfaces!
	//s.Translucency = lerp(o.Translucency, o.Translucency * 0.2, saturate(snow.x + snow.y) );
	s.specColor = lerp(s.specColor, _Lux_SnowSpecColor2.rgb, snow.xxx);
	s.smoothness = lerp(s.smoothness, _Lux_SnowSpecColor2.a, snow.x);
	s.oneMinusReflectivity = 1.0 - s.smoothness;
	// Smooth normals a bit
	//s.Normal = lerp(o.Normal, half3(0, 0, 1), snow.xxx * 0.5);
	//s.Occlusion = lerp(o.Occlusion, 1.0, snow.x);
}*/
#else
	#define ApplySnowEffectsPre(vertexNormal)
	#define ApplySnowEffects(s, occlusion, uv)
#endif

#if defined(_SIMPLE_WATER)
half _FillRatio;
#include "Packages/com.uboat.assemblies/DeepRenderPipeline/Utility/NoiseLib.cginc"

half3 GetWaterNormals(float4 texcoords, float3 worldPos)
{
	float2 perlinWorldPos = worldPos.xz * 2.5;
	float perlin_x = Perlin3D(float3(perlinWorldPos.x, _Time.y, perlinWorldPos.y));
	float perlin_y = Perlin3D(float3(perlinWorldPos.x + 131.171, _Time.y, perlinWorldPos.y));

	texcoords.xy += float2(perlin_x, perlin_y) * _PerlinIntensity;

	half2 uv1 = texcoords.xy + _Time.xx * half2(10, 10);
	half2 uv2 = texcoords.xy * 1.5 + _Time.xx * half2(-8.1, -11.1);

	return UnpackScaleNormal(tex2D(_BumpMap, uv1), _BumpScale) + UnpackScaleNormal(tex2D(_BumpMap, uv2), _BumpScale);
}
#endif

#endif