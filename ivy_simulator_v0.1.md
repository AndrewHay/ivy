# Ivy Simulator v0.1

A computationally inexpensive runtime model for ivy and climbing-vine growth over arbitrary 3D structures.

The simulator combines:

- Thomas Luft–style local geometry and attachment mechanics.
- Dynamic environmental light exposure.
- Light-memory / accumulated-light response.
- Environment-dependent growth rate.
- Environment-dependent exploration and phototropism.
- Distance-based branching.
- Crowding avoidance.
- Cheap unsupported-vine gravity and death rules.

The central architectural principle is:

\[
\boxed{\text{Environment}}
\rightarrow
\boxed{\text{Plant physiology}}
\rightarrow
\boxed{\text{Geometry}}
\]

Environmental conditions are mutable simulation state. The ivy does **not** need to be regenerated if the lighting environment changes.

For example, adding an awning, moving a neighboring object, changing latitude, changing season, or introducing cloud cover can alter future growth during the simulation.

---

## 1. Relationship to Thomas Luft's Ivy Generator

Thomas Luft's Ivy Generator uses a small set of local influences to generate convincing ivy geometry:

- Previous growth direction.
- Random variation.
- Attraction toward nearby surfaces.
- An upward bias approximating phototropism.
- Gravity.

Reference:

- Thomas Luft, *Ivy Generator*: https://graphics.uni-konstanz.de/~luft/ivy_generator/

The Blender implementation derived from the same approach adds useful concrete mechanics including:

- Nearest-surface queries.
- Distance-dependent adhesion.
- Collision correction.
- Increasing gravity while unsupported.
- Death after excessive unsupported growth.
- Direction smoothing.

Reference:

- Blender IvyGen discussion / implementation notes: https://blenderartists.org/t/ivy-addon-small-changes/1309600

### What this simulator keeps from Luft

- Active growth tips.
- Persistent direction.
- Stochastic exploration.
- Nearest-surface attraction.
- 3D growth rather than rigidly projecting vines onto the wall.
- Collision correction.
- Floating/unsupported length.
- Progressive gravity.
- Death after excessive unsupported growth.
- Direction smoothing.

### What this simulator replaces or adds

Luft's approximate:

\[
\text{phototropism} \approx \text{up}
\]

is replaced by a dynamic environmental light field.

The simulator also adds:

- Accumulated light history.
- Environment-dependent growth rate.
- Light-dependent exploratory behavior.
- Surface light gradients.
- Crowding.
- Distance-based branching.
- Optional moisture.
- Runtime environmental changes.

The intended architecture is therefore:

\[
\boxed{
\text{Luft-style local geometry}
+
\text{dynamic environmental fields}
}
\]

---

# 2. Simulation Layers

The simulator has three independent layers.

## 2.1 Environment

Produces values such as:

- Instantaneous light.
- Accumulated light.
- Light gradient.
- Surface material.
- Moisture.
- Existing ivy density.

## 2.2 Plant physiology

Converts environmental state into:

- Growth speed.
- Persistence.
- Random exploration.
- Phototropism.
- Branching probability.

## 2.3 Geometry

Determines the physical location of the next vine segment using:

- Persistence.
- Randomness.
- Surface adhesion.
- Light seeking.
- Crowding avoidance.
- Gravity.
- Collision response.

This separation is important because an environmental change can affect future growth without moving or regenerating existing stems.

---

# 3. Per-Tip State

Only actively growing tips require simulation.

Each tip stores:

| Variable | Meaning | Unit |
|---|---|---|
| \(\mathbf{x}\) | Current tip position | m |
| \(\mathbf{P}\) | Persistent growth direction | unit vector |
| \(\mathbf{R}\) | Correlated random direction | unit vector |
| \(B\) | Available growth budget | m |
| \(F\) | Continuous unsupported/floating length | m |
| \(s\) | Total shoot length | m |
| \(o\) | Branch order | integer |
| `seed` | Deterministic RNG state | — |

Most of the already-grown vine remains static.

---

# 4. Light Representation

The simulator distinguishes between:

\[
P(\mathbf{x},t)
\]

instantaneous photosynthetically useful light, and:

\[
D_L(\mathbf{x},t)
\]

accumulated / remembered light exposure.

This distinction prevents unrealistic behavior in which the plant continually changes direction toward the instantaneous position of the sun.

The plant primarily responds to accumulated light.

---

# 5. Solar Position

The sun direction is:

\[
\mathbf{S}(t)
\]

and may be calculated from:

- Latitude.
- Longitude.
- Date.
- Time.

A standard solar-position model can be used.

NOAA reference:

https://gml.noaa.gov/grad/solcalc/solareqns.PDF

At a surface point \(\mathbf{x}\), let:

- \(\mathbf{n}\) = surface normal.
- \(\alpha\) = solar elevation.
- \(V(\mathbf{x},t)\in[0,1]\) = direct-sun visibility.
- \(SVF(\mathbf{x})\in[0,1]\) = sky-view factor.
- \(W(t)\) = direct-light weather multiplier.
- \(W_{\text{sky}}(t)\) = diffuse-light weather multiplier.

Then total instantaneous light is:

\[
P(\mathbf{x},t)
=
P_{\text{dir}}
+
P_{\text{diff}}
+
P_{\text{artificial}}
\]

with:

\[
P_{\text{dir}}
=
P_{\max}
W(t)
V(\mathbf{x},t)
[\max(0,\sin\alpha)]^{0.65}
\max(0,\mathbf{n}\cdot\mathbf{S})
\]

and:

\[
P_{\text{diff}}
=
P_{\text{sky}}
W_{\text{sky}}(t)
[\max(0,\sin\alpha)]^{0.5}
SVF(\mathbf{x})
\]

Initial game-calibration values:

\[
P_{\max}=1600\ \mu mol\,m^{-2}s^{-1}
\]

\[
P_{\text{sky}}=180\ \mu mol\,m^{-2}s^{-1}
\]

These should be treated as simulation defaults rather than fitted *Hedera helix* physiological constants.

---

# 6. Runtime Light Changes

Direct-sun visibility is explicitly mutable:

\[
V(\mathbf{x},t)\in[0,1]
\]

For example, adding an awning may cause:

\[
V:1\rightarrow0
\]

at affected locations.

This immediately changes instantaneous light.

Other possible runtime changes include:

- Moving geometry.
- New vegetation.
- Cloud cover.
- Seasonal change.
- Time-of-day progression.
- Latitude changes.
- Artificial lighting.
- Destruction of an obstruction.
- Construction of an obstruction.

The existing vine geometry remains unchanged. Future growth responds to the new environment.

---

# 7. Accumulated Light / Light Memory

Store an exponentially weighted mean light level:

\[
\bar P_L
\]

For an environmental simulation timestep \(\Delta t\), define:

\[
a=e^{-\Delta t/\tau_L}
\]

and update:

\[
\boxed{
\bar P_L^{new}
=
a\bar P_L^{old}
+
(1-a)P(\mathbf{x},t)
}
\]

where:

\[
\tau_L=3\text{ game-days}
\]

is the initial light-memory constant.

Convert this mean light level to a convenient DLI-equivalent quantity:

\[
\boxed{
D_L=0.0864\,\bar P_L
}
\]

because:

\[
86400 / 10^6 = 0.0864
\]

Thus \(D_L\) is approximately expressed in:

\[
mol\,m^{-2}day^{-1}
\]

This is an intentionally game-friendly continuous analogue of Daily Light Integral.

Reference on DLI:

https://www.canr.msu.edu/uploads/resources/pdfs/dailylightintegraldefined.pdf

---

# 8. Example: Shade Added During Simulation

Suppose a surface historically experiences:

\[
D_L=12
\]

and an environmental change causes its new long-term equivalent to become:

\[
D_{\text{target}}=3
\]

With:

\[
\tau_L=3\text{ days}
\]

the remembered light state evolves approximately as:

\[
\boxed{
D_L(t)
=
3+(12-3)e^{-t/3}
}
\]

The plant therefore does not instantly behave as though it has always lived in deep shade.

Instead, its physiological state gradually converges toward the new environment.

This gives the simulator useful environmental memory.

---

# 9. Direct Manipulation of Light History

Two separate operations should exist.

## 9.1 Change current environmental illumination

Conceptually:

```text
set_current_light(region, value)
```

This changes:

\[
P(\mathbf{x},t)
\]

The accumulated state then naturally adapts according to the light-memory equation.

## 9.2 Change accumulated light directly

Conceptually:

```text
set_accumulated_light(region, value)
```

This directly changes:

\[
D_L
\]

For gradual scripted changes:

\[
D_L
\leftarrow
(1-\beta)D_L+\beta D_{\text{target}}
\]

where:

\[
0\leq\beta\leq1
\]

These operations intentionally have different meanings.

---

# 10. Light Response Function

Convert accumulated light into a normalized light-health response:

\[
\boxed{
f_L(D)
=
\min
\left[
1,
\frac{D/(D+K_L)}
{D_{ref}/(D_{ref}+K_L)}
\right]
}
\]

Default parameters:

\[
K_L=3
\]

\[
D_{ref}=12
\]

Therefore:

\[
f_L(12)=1
\]

At:

\[
D=3
\]

the result is approximately:

\[
f_L\approx0.625
\]

This deliberately represents ivy as relatively shade tolerant.

Research on juvenile *Hedera helix* demonstrates development over a broad range of light environments:

https://link.springer.com/article/10.1007/s11258-023-01354-w

The values \(K_L=3\) and \(D_{ref}=12\) are simulation calibration parameters rather than fitted constants from that study.

---

# 11. Combined Environmental Health

Define:

\[
H=f_L(D_L)f_M(M)
\]

where \(M\) is moisture availability.

For v0.1, moisture may be disabled by simply setting:

\[
f_M=1
\]

Thus:

\[
H=f_L
\]

until the moisture model is implemented.

---

# 12. Persistence

The persistence weight determines how strongly a tip continues in its previous direction.

Define:

\[
\boxed{
w_P=0.5(0.7+0.3H)
}
\]

Therefore:

Healthy vine:

\[
H=1
\Rightarrow
w_P=0.5
\]

Very unhealthy vine:

\[
H=0
\Rightarrow
w_P=0.35
\]

Poorly supported environmental conditions therefore make the vine less committed to its current trajectory.

---

# 13. Random Exploration

Define:

\[
\boxed{
w_R=
0.2[1+0.8(1-H)]
}
\]

Healthy:

\[
H=1
\Rightarrow
w_R=0.20
\]

Highly stressed:

\[
H=0
\Rightarrow
w_R=0.36
\]

Thus poor conditions increase exploratory movement.

---

# 14. Correlated Randomness

Rather than generating an unrelated random vector for every segment, maintain a correlated random direction.

Generate a random unit vector:

\[
\boldsymbol{\xi}
\]

Then update:

\[
\boxed{
\mathbf{R}_{new}
=
normalize
(
0.75\mathbf{R}
+
0.25\boldsymbol{\xi}
)
}
\]

This produces wandering rather than jitter.

The mixing value can later become a species parameter.

Examples:

| Mix toward new randomness | Appearance |
|---:|---|
| 0.05 | Long, smooth runners |
| 0.25 | Default ivy |
| 0.60 | Highly erratic tendrils |

---

# 15. Phototropism Strength

Phototropism should become stronger when the plant is poorly illuminated.

Define:

\[
\boxed{
w_L=
0.03+0.20(1-f_L)
}
\]

In good light:

\[
f_L=1
\Rightarrow
w_L=0.03
\]

In severe shade:

\[
f_L\rightarrow0
\Rightarrow
w_L\rightarrow0.23
\]

Thus a well-lit vine largely ignores better-light gradients.

A shaded vine actively searches for them.

---

# 16. Light-Seeking Direction

Do **not** use the current sun vector as the phototropic direction.

Instead use the gradient of accumulated light:

\[
\nabla D_L
\]

For surface-following behavior use the surface gradient:

\[
\nabla_S D_L
\]

Define the bounded light direction:

\[
\boxed{
\mathbf{L}
=
\frac{\nabla_S D_L}
{\|\nabla_S D_L\|+g_L}
}
\]

with:

\[
g_L=4
\frac{mol\,m^{-2}day^{-1}}{m}
\]

This prevents very sharp shadow boundaries from generating arbitrarily strong directional forces.

A numerical gradient can be estimated using nearby samples.

For tangent direction \(\mathbf{u}\):

\[
\frac{\partial D}{\partial u}
\approx
\frac{
D(\mathbf{x}+\epsilon\mathbf{u})
-
D(\mathbf{x}-\epsilon\mathbf{u})
}{
2\epsilon
}
\]

and similarly for the second tangent direction \(\mathbf{v}\).

This can be implemented with approximately four field samples per growth event.

---

# 17. Surface Adhesion

Use a Luft-style nearest-surface attraction model.

Let:

\[
\mathbf{q}
=
NearestSurface(\mathbf{x})
\]

and:

\[
d=\|\mathbf{q}-\mathbf{x}\|
\]

Then:

\[
\boxed{
\mathbf{A}
=
A_m
\max
\left(
0,
1-\frac{d}{d_A}
\right)
\frac{\mathbf{q}-\mathbf{x}}{d}
}
\]

Default adhesion range:

\[
d_A=0.15m
\]

where:

\[
A_m\in[0,1]
\]

represents surface attachment suitability.

Possible initial gameplay values:

| Surface | \(A_m\) |
|---|---:|
| Rough brick | 1.00 |
| Rough stone | 1.00 |
| Rough concrete | 0.80 |
| Painted masonry | 0.50 |
| Smooth metal | 0.30 |
| Glass | 0.05 |

These values are gameplay tuning parameters.

The key behavior is the linear distance falloff:

\[
1-\frac{d}{d_A}
\]

which closely follows Luft/IvyGen's adhesion approach.

---

# 18. Crowding Field

Maintain an ivy-density field:

\[
C(\mathbf{x})\in[0,1]
\]

Calculate a surface crowding gradient:

\[
\nabla_S C
\]

and define:

\[
\mathbf{C}
=
\frac{\nabla_S C}
{\|\nabla_S C\|+2}
\]

Crowding avoidance strength:

\[
\boxed{
w_C=0.15(0.5+0.5H)
}
\]

Healthy plants therefore expand slightly more strongly into empty territory.

Crowding also affects growth rate:

\[
\boxed{
f_C=e^{-0.8C}
}
\]

At maximum crowding:

\[
C=1
\Rightarrow
f_C\approx0.45
\]

Overlap is therefore discouraged but not forbidden.

---

# 19. Unsupported Growth

Track:

\[
F
\]

the continuous unsupported length.

While the vine remains attached:

\[
F=0
\]

While unsupported:

\[
F\leftarrow F+\Delta s
\]

Set:

\[
F_{\max}=0.40m
\]

and calculate:

\[
r_F=
clamp
\left(
\frac{F}{F_{\max}},
0,
1
\right)
\]

---

# 20. Progressive Gravity

Use the Luft/IvyGen-style gravity progression:

\[
\boxed{
w_G=r_F^{0.7}
}
\]

The gravity direction is:

\[
\mathbf{G}=(0,0,-1)
\]

At small unsupported lengths, gravity has limited influence.

As unsupported length increases, the vine progressively sags.

If:

\[
F>F_{\max}
\]

the growth tip dies.

When contact is regained:

\[
F=0
\]

This creates:

- Short bridges.
- Hanging runners.
- Reattachment.
- Natural failure when no support can be reached.

without requiring full soft-body physics.

---

# 21. Final Growth Direction

Combine all directional influences:

\[
\boxed{
\mathbf{U}
=
w_P\mathbf{P}
+
w_R\mathbf{R}
+
0.10\mathbf{A}
+
w_L\mathbf{L}
-
w_C\mathbf{C}
+
w_G\mathbf{G}
}
\]

Normalize:

\[
\boxed{
\mathbf{d}
=
\frac{\mathbf{U}}
{\|\mathbf{U}\|}
}
\]

Default segment length:

\[
h=0.03m
\]

Propose:

\[
\boxed{
\mathbf{x}_{trial}
=
\mathbf{x}
+
h\mathbf{d}
}
\]

Each growth event therefore creates approximately 3 cm of stem.

---

# 22. Collision Handling

Raycast or sweep from:

\[
\mathbf{x}
\]

to:

\[
\mathbf{x}_{trial}
\]

If no collision occurs:

\[
\mathbf{x}_{new}=\mathbf{x}_{trial}
\]

If geometry is penetrated, use a Luft-style collision correction.

Conceptually:

\[
\mathbf{r}
=
reflect(
\mathbf{x}_{trial}-\mathbf{x}_{hit},
\mathbf{n}
)
\]

Then:

\[
\mathbf{x}_{new}
=
\mathbf{x}_{hit}
+
\mathbf{r}
\]

where:

- \(\mathbf{x}_{hit}\) is the collision point.
- \(\mathbf{n}\) is the surface normal.

The exact implementation can later use raycasts, spherecasts, BVH queries, or a signed-distance field.

---

# 23. Persistent Direction Update

Calculate the actual movement direction:

\[
\mathbf{d}_{actual}
=
normalize(
\mathbf{x}_{new}-\mathbf{x}
)
\]

Update persistent direction:

\[
\boxed{
\mathbf{P}_{new}
=
normalize
(
0.5\mathbf{P}
+
0.5\mathbf{d}_{actual}
)
}
\]

This preserves the useful directional smoothing behavior found in IvyGen.

The value `0.5` should eventually be exposed as a species or stiffness parameter.

---

# 24. Growth Rate

Geometry creation is decoupled from the simulation timestep.

Define maximum elongation rate:

\[
r_{\max}=0.12m/\text{game-day}
\]

Actual growth rate:

\[
\boxed{
r=
r_{\max}
f_L
f_M
f_C
f_S
}
\]

where the unsupported-support penalty is:

\[
\boxed{
f_S=
1-
0.5
\left(
\frac{F}{F_{\max}}
\right)^2
}
\]

As the vine becomes increasingly unsupported, elongation slows.

---

# 25. Growth Budget

Each active tip stores:

\[
B
\]

in metres of available growth.

Update:

\[
\boxed{
B_{new}
=
B_{old}
+
r\Delta t
}
\]

Whenever:

\[
B\geq h
\]

create one segment and subtract:

\[
B\leftarrow B-h
\]

This is one of the most important runtime optimizations.

The environment can be updated frequently while geometry changes only when sufficient plant growth has accumulated.

---

# 26. Branching

Branching should be defined per metre of actual growth rather than per simulation tick.

Set baseline branch rate:

\[
\lambda_0=1.7m^{-1}
\]

Then:

\[
\boxed{
\lambda_b
=
1.7
f_L^{1.3}
f_M
(1-C)^{1.5}
}
\]

For a newly created segment of length \(h\), branching probability is:

\[
\boxed{
p_b
=
1-e^{-\lambda_bh}
}
\]

At:

\[
h=0.03m
\]

and ideal conditions:

\[
p_b
\approx
1-e^{-1.7(0.03)}
\approx
0.05
\]

or roughly 5% branching probability per 3 cm segment.

Because the probability is based on distance grown rather than update count, changing simulation tick rate does not change the plant's branching statistics.

---

# 27. Runtime Shade Example

Suppose:

\[
\tau_L=3\text{ days}
\]

and a wall changes from a DLI-equivalent of:

\[
D=12
\]

to:

\[
D=3
\]

The remembered light state gradually declines.

Approximate resulting behavior:

| Days after shade | Stored \(D_L\) | \(f_L\) | Light-seeking \(w_L\) | Randomness \(w_R\) | Branch chance / 3 cm |
|---:|---:|---:|---:|---:|---:|
| 0 | 12.00 | 1.000 | 0.030 | 0.200 | 4.97% |
| 1 | 9.45 | 0.949 | 0.040 | 0.208 | 4.65% |
| 3 | 6.31 | 0.847 | 0.061 | 0.224 | 4.03% |
| 6 | 4.22 | 0.730 | 0.084 | 0.243 | 3.33% |
| 9 | 3.45 | 0.668 | 0.096 | 0.253 | 2.98% |

A single environmental change therefore causes several emergent behavioral changes:

- Growth slows.
- Persistence decreases.
- Random exploration increases.
- Light-seeking increases.
- Branching decreases.

These effects arise from shared equations rather than separate scripted rules.

---

# 28. Minimal Environment Update

Conceptually:

```text
environment_update(dt):

    sun = calculate_sun(
        latitude,
        longitude,
        date,
        time
    )

    for each relevant surface sample:

        P_direct =
            max_direct_light
            * weather_direct
            * visibility
            * solar_elevation_factor
            * surface_incidence

        P_diffuse =
            diffuse_light
            * weather_diffuse
            * diffuse_elevation_factor
            * sky_view_factor

        P =
            P_direct
            + P_diffuse
            + artificial_light

        a = exp(-dt / light_memory)

        mean_light =
            a * previous_mean_light
            + (1 - a) * P

        accumulated_light =
            0.0864 * mean_light
```

---

# 29. Minimal Plant Update

Conceptually:

```text
plant_update(dt):

    for each active_tip:

        D = sample_accumulated_light(tip.position)
        C = sample_crowding(tip.position)
        M = sample_moisture(tip.position)

        f_light = light_response(D)
        f_moisture = moisture_response(M)

        H = f_light * f_moisture

        persistence_weight =
            0.5 * (0.7 + 0.3 * H)

        random_weight =
            0.2 * (1 + 0.8 * (1 - H))

        light_seek_weight =
            0.03 + 0.20 * (1 - f_light)

        crowd_weight =
            0.15 * (0.5 + 0.5 * H)

        growth_rate =
            max_growth_rate
            * f_light
            * f_moisture
            * crowd_response(C)
            * support_response(tip.floating_length)

        tip.growth_budget += growth_rate * dt

        while tip.growth_budget >= segment_length:

            adhesion =
                calculate_surface_adhesion(tip)

            light_direction =
                calculate_light_gradient(tip)

            crowd_direction =
                calculate_crowding_gradient(tip)

            gravity =
                calculate_unsupported_gravity(tip)

            direction =
                persistence_weight * tip.persistence
                + random_weight * tip.random_direction
                + 0.10 * adhesion
                + light_seek_weight * light_direction
                - crowd_weight * crowd_direction
                + gravity

            direction = normalize(direction)

            trial_position =
                tip.position
                + segment_length * direction

            new_position =
                resolve_collision(
                    tip.position,
                    trial_position
                )

            update_floating_length(tip, new_position)

            actual_direction =
                normalize(
                    new_position - tip.position
                )

            tip.persistence =
                normalize(
                    0.5 * tip.persistence
                    + 0.5 * actual_direction
                )

            tip.random_direction =
                update_correlated_random_direction(
                    tip.random_direction
                )

            create_segment(
                tip.position,
                new_position
            )

            tip.position = new_position

            update_crowding_field(new_position)

            maybe_create_branch(tip)

            tip.growth_budget -= segment_length

            if tip.floating_length > max_float:
                kill_tip(tip)
                break
```

---

# 30. Default Parameters

| Parameter | Default | Purpose |
|---|---:|---|
| `segment_length` | 0.03 m | Geometric resolution |
| `max_growth_rate` | 0.12 m/day | Maximum elongation |
| `light_memory` | 3 days | Light-history persistence |
| `light_K` | 3 DLI | Shade tolerance |
| `reference_DLI` | 12 | Light reference / saturation |
| `persistence_base` | 0.50 | Directional straightness |
| `random_base` | 0.20 | Exploratory wandering |
| `random_new_mix` | 0.25 | Random-direction variation |
| `light_seek_min` | 0.03 | Phototropism in good light |
| `light_seek_max` | 0.23 | Phototropism in severe shade |
| `adhesion_base` | 0.10 | Surface attraction contribution |
| `adhesion_range` | 0.15 m | Maximum useful support distance |
| `max_float` | 0.40 m | Maximum unsupported length |
| `gravity_exponent` | 0.70 | Sag progression |
| `crowding_base` | 0.15 | Empty-space preference |
| `crowding_decay` | 0.80 | Crowding effect on growth |
| `branch_rate` | 1.7 /m | Baseline branching frequency |
| `branch_light_exponent` | 1.30 | Light sensitivity of branching |
| `branch_crowd_exponent` | 1.50 | Crowding sensitivity of branching |
| `direction_memory` | 0.50 | Direction smoothing |
| `light_gradient_scale` | 4 DLI/m | Bounds light-gradient force |

All of these should be exposed in a development build.

The initial values are starting points for visual calibration rather than a claim of exact ivy physiology.

---

# 31. Causal Model

The simulator's intended causal chain is:

\[
\boxed{
\text{Sun / shade / weather / geometry}
}
\]

\[
\downarrow
\]

\[
\boxed{
P(\mathbf{x},t)
}
\]

instantaneous light

\[
\downarrow
\]

\[
\boxed{
D_L(\mathbf{x},t)
}
\]

accumulated light history

\[
\downarrow
\]

\[
\boxed{
f_L
}
\]

light-health state

\[
\downarrow
\]

\[
\boxed{
\begin{array}{c}
\text{growth speed}\\
\text{persistence}\\
\text{exploration}\\
\text{phototropism}\\
\text{branching}
\end{array}
}
\]

\[
\downarrow
\]

\[
\boxed{
\text{Luft-derived 3D growth mechanics}
}
\]

This gives a runtime simulator rather than a procedural mesh generator.

---

# 32. Important Design Properties

The model intentionally has the following properties.

## Dynamic lighting

Accumulated light can change during a simulation.

## Environmental memory

The plant does not instantly forget its previous lighting conditions.

## Timestep independence

Growth and branching depend on simulated time and distance rather than frame count.

## Sparse simulation

Only active tips require meaningful plant computation.

## Cheap geometry interaction

Nearest-surface queries and collision checks replace full vine physics.

## Natural unsupported behavior

Vines can:

- Leave a surface.
- Bridge small gaps.
- Sag.
- Reattach.
- Fail and die.

## Emergent shade response

Reduced light automatically produces:

- Slower growth.
- Fewer branches.
- Greater exploration.
- Stronger light seeking.

without individually scripting those behaviors.

---

# 33. Recommended Next Engineering Decision

The next major implementation decision is how to store environmental surface state.

Candidate approaches:

1. **UV-space environmental textures**
   - Light history.
   - Crowding.
   - Moisture.
   - Material properties.

2. **World-space voxel or sparse hash field**
   - More general.
   - Works without clean UVs.
   - More expensive.

3. **Local state only around active tips**
   - Cheapest.
   - Harder to maintain persistent environmental history over entire buildings.

For large static architecture, UV-space or surface-atlas fields are likely to be the strongest starting point.

For arbitrary destructible or moving geometry, a sparse world-space representation may eventually be preferable.

---

# 34. Research References

### Thomas Luft — Ivy Generator

https://graphics.uni-konstanz.de/~luft/ivy_generator/

### Blender IvyGen implementation discussion

https://blenderartists.org/t/ivy-addon-small-changes/1309600

### NOAA solar-position equations

https://gml.noaa.gov/grad/solcalc/solareqns.PDF

### Daily Light Integral overview

https://www.canr.msu.edu/uploads/resources/pdfs/dailylightintegraldefined.pdf

### *Hedera helix* response to light environment

https://link.springer.com/article/10.1007/s11258-023-01354-w

### Interactive Modeling and Authoring of Climbing Plants

https://diglib.eg.org/items/91f715b4-810f-4f55-b7ac-ee36c0ba1ed6

---

# 35. Summary

The simulator can be summarized as:

\[
\boxed{
\text{Dynamic environment}
+
\text{light memory}
+
\text{environment-dependent plant behavior}
+
\text{Luft-style geometry}
}
\]

The defining difference from Thomas Luft's Ivy Generator is that the generated structure is no longer merely the product of local geometric heuristics.

Instead:

\[
\text{environment}
\rightarrow
\text{plant state}
\rightarrow
\text{growth behavior}
\rightarrow
\text{geometry}
\]

and all of those environmental inputs can change while the simulation is running.
