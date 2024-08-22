#ifndef DEEP_TREE_INCLUDED
#define DEEP_TREE_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/UnityInstancing.hlsl"

#if defined(_TREE_LEAVES_MANUFACTURE) && !defined(_TRANSLUCENCY)
	#define _TRANSLUCENCY
#endif

#define FLT_EPSILON 1.192092896e-07 

sampler2D WIND_SETTINGS_TexNoise;
sampler2D WIND_SETTINGS_TexGust;

float _InitialBend;
float _Stiffness;
float _Drag;
float _ShiverDrag;
float _ShiverDirectionality;
float4 _NewNormal;


float4  WIND_SETTINGS_WorldDirectionAndSpeed;
float   WIND_SETTINGS_FlexNoiseScale;
float   WIND_SETTINGS_ShiverNoiseScale;
float   WIND_SETTINGS_Turbulence;
float   WIND_SETTINGS_GustSpeed;
float   WIND_SETTINGS_GustScale;
float   WIND_SETTINGS_GustWorldScale;

float4x4 GetObjectToWorldMatrix()
{
    return unity_ObjectToWorld;
}

float4x4 GetWorldToObjectMatrix()
{
    return unity_WorldToObject;
}

float3 TransformObjectToWorld(float3 positionOS)
{
    return mul(GetObjectToWorldMatrix(), float4(positionOS, 1.0)).xyz;
}


float3 TransformObjectToWorldNormal(float3 normalOS)
{
#ifdef UNITY_ASSUME_UNIFORM_SCALING
    return UnityObjectToWorldDir(normalOS);
#else
    // Normal need to be multiply by inverse transpose
    // mul(IT_M, norm) => mul(norm, I_M) => {dot(norm, I_M.col0), dot(norm, I_M.col1), dot(norm, I_M.col2)}
    return normalize(mul(normalOS, (float3x3)GetWorldToObjectMatrix()));
#endif
}

float3 TransformWorldToObject(float3 positionWS)
{
    return mul(GetWorldToObjectMatrix(), float4(positionWS, 1.0)).xyz;
}

//float PositivePow(float base, float power)
//{
//   return pow(max(abs(base), float(FLT_EPSILON)), power);
//}

float AttenuateTrunk(float x, float s)
{
    float r = (x / s);
    return PositivePow(r,1/s);
}


float3 Rotate(float3 pivot, float3 position, float3 rotationAxis, float angle)
{
    rotationAxis = normalize(rotationAxis);
    float3 cpa = pivot + rotationAxis * dot(rotationAxis, position - pivot);
    return cpa + ((position - cpa) * cos(angle) + cross(rotationAxis, (position - cpa)) * sin(angle));
}

struct WindData
{
    float3 Direction;
    float Strength;
    float3 ShiverStrength;
    float3 ShiverDirection;
};


float3 texNoise(float3 worldPos, float LOD)
{
	return tex2Dlod(WIND_SETTINGS_TexNoise,float4(worldPos.xz,0,LOD)).xyz -0.5;
}

float texGust(float3 worldPos, float LOD)
{
    return tex2Dlod(WIND_SETTINGS_TexGust, float4(worldPos.xz,0, LOD)).x;
}


WindData GetAnalyticalWind(float3 WorldPosition, float3 PivotPosition, float drag, float shiverDrag, float initialBend, float4 time)
{
    WindData result;
    float3 normalizedDir = normalize(WIND_SETTINGS_WorldDirectionAndSpeed.xyz);

    float3 worldOffset = normalizedDir * WIND_SETTINGS_WorldDirectionAndSpeed.w * time.y;
    float3 gustWorldOffset = normalizedDir * WIND_SETTINGS_GustSpeed * time.y;

    // Trunk noise is base wind + gusts + noise

    float3 trunk = float3(0,0,0);

    if(WIND_SETTINGS_WorldDirectionAndSpeed.w > 0.0 || WIND_SETTINGS_Turbulence > 0.0)
    {
        trunk = texNoise((PivotPosition - worldOffset)*WIND_SETTINGS_FlexNoiseScale,3);
    }

    float gust  = 0.0;

    if(WIND_SETTINGS_GustSpeed > 0.0)
    {
        gust = texGust((PivotPosition - gustWorldOffset)*WIND_SETTINGS_GustWorldScale,3);
        gust = pow(gust, 2) * WIND_SETTINGS_GustScale;
    }

    float3 trunkNoise =
        (
                (normalizedDir * WIND_SETTINGS_WorldDirectionAndSpeed.w)
                + (gust * normalizedDir * WIND_SETTINGS_GustSpeed)
                + (trunk * WIND_SETTINGS_Turbulence)
        ) * drag;

    // Shiver Noise
    float3 shiverNoise = texNoise((WorldPosition - worldOffset)*WIND_SETTINGS_ShiverNoiseScale,0) * shiverDrag * WIND_SETTINGS_Turbulence;

    float3 dir = trunkNoise;
    float flex = length(trunkNoise) + initialBend;
    float shiver = length(shiverNoise);

    result.Direction = dir;
    result.ShiverDirection = shiverNoise;
    result.Strength = flex;
    result.ShiverStrength = shiver + shiver * gust;

    return result;
}



void ApplyWindDisplacement( inout float3    positionWS,
							inout float    windStrength,
                            float3          normalWS,
                            float3          rootWP,
                            float           stiffness,
                            float           drag,
                            float           shiverDrag,
                            float           shiverDirectionality,
                            float           initialBend,
                            float           shiverMask,
                            float4          time
							)
{
    WindData wind = GetAnalyticalWind(positionWS, rootWP, drag, shiverDrag, initialBend, time);

    if (wind.Strength > 0.0)
    {
        float att = AttenuateTrunk(distance(positionWS, rootWP), stiffness);
        float3 rotAxis = cross(float3(0, 1, 0), wind.Direction);

        positionWS = Rotate(rootWP, positionWS, rotAxis, (wind.Strength) * 0.001 * att);

        float3 shiverDirection = normalize(lerp(normalWS, normalize(wind.Direction + wind.ShiverDirection), shiverDirectionality));
        positionWS += wind.ShiverStrength * shiverDirection * shiverMask;

		windStrength = wind.Strength;
    }
}

void CalculateWind(inout VertexInput v)
{
	float3 positionWS = TransformObjectToWorld(v.vertex.xyz);

    float3 rootWP = mul(GetObjectToWorldMatrix(), float4(0, 0, 0, 1)).xyz;

	float3 normalWS =  TransformObjectToWorldNormal(v.normal);

	float windStrength = 0;

	ApplyWindDisplacement( positionWS, windStrength, normalWS, rootWP, _Stiffness, _Drag, _ShiverDrag, _ShiverDirectionality, _InitialBend, v.color.a, _Time);

	v.vertex.xyz = TransformWorldToObject(positionWS).xyz;

	v.color.r = windStrength;

	if (_NewNormal.x != 0 || _NewNormal.y != 0 || _NewNormal.z != 0)
		v.normal *= _NewNormal;
}

void CalculateWindMV(inout MotionVertexInput v)
{
	float3 positionWS = TransformObjectToWorld(v.vertex.xyz);

    float3 rootWP = mul(GetObjectToWorldMatrix(), float4(0, 0, 0, 1)).xyz;

	float3 normalWS =  TransformObjectToWorldNormal(v.normal);

	float windStrength = 0;

	ApplyWindDisplacement( positionWS, windStrength, normalWS, rootWP, _Stiffness, _Drag, _ShiverDrag, _ShiverDirectionality, _InitialBend, v.color.a, _Time);

	v.vertex.xyz = TransformWorldToObject(positionWS).xyz;

	v.color.r = windStrength;

	if (_NewNormal.x != 0 || _NewNormal.y != 0 || _NewNormal.z != 0)
		v.normal *= _NewNormal;
}

void ApplyTreeEffects(inout FragmentCommonData s, fixed color, inout half3 translucency, inout float occlusion, float2 uv)
{
	translucency = _TranslucencyStrength;

#if defined(_TREE_BARK_MANUFACTURE)
    occlusion *= 0.65;
#endif

#if defined(_TREE_LEAVES_MANUFACTURE) && !defined(IMPOSTOR_BAKE)
    half3 shiftedColor = lerp(s.diffColor.rgb, lerp(_HueVariation.rgb, _HueVariationAutumn.rgb, _SeasonBlendFactor), color);
	half maxBase = max(s.diffColor.r, max(s.diffColor.g, s.diffColor.b));
	half newMaxBase = max(shiftedColor.r, max(shiftedColor.g, shiftedColor.b));
	maxBase /= newMaxBase;
	maxBase = maxBase * 0.5f + 0.5f;
	shiftedColor.rgb *= maxBase;
	s.diffColor.rgb = saturate(shiftedColor);
#endif
}


#endif
