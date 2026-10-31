# Arsène build step 1: physical assembly

> Historical assembly planning record retained from local commit `b74afb1`
> (2026-10-11T09:57:19-05:00). Arsene is now an operating host. Unchecked items and TODO values
> below identify missing contemporaneous evidence; they do not establish
> current failures or request another physical build. No missing firmware,
> temperature, power or serial-number measurements have been reconstructed.
> Original office photographs and layout drafts remain in private evidence.

Jira: [KAN-131](https://brownrook.atlassian.net/browse/KAN-131)

This checklist covers the first build item in KAN-131: assembling the CPU,
cooler, memory, NVMe, motherboard, power supply, and RTX 3090 in the case. It
also captures the hardware details needed for a reproducible rebuild record.

## Confirmed chassis and cooling layout

The chassis label confirms the newer modular Corsair FRAME 4000D WOOD, not the
original 4000D.

- The FRAME 4000 series supports a 360 mm radiator at the top, front, or side
  and lists 430 mm maximum GPU length.
- The ARCTIC Liquid Freezer III Pro 360 radiator is 398 x 120 x 38 mm; the
  radiator and fans are approximately 66 mm thick together.
- The EVGA RTX 3090 FTW3 is approximately 300 mm long, 136.75 mm high, and
  55.55 mm thick.

The photo shows three factory front fans and one rear fan. Keep the front bank
as intake and the rear fan as exhaust. Prefer the 360 mm radiator at the top as
exhaust so the GPU receives fresh front intake air. Because this cooler is
unusually thick, dry-fit the complete 66 mm radiator/fan assembly and check
motherboard VRM-heatsink, memory, and CPU-EPS-cable clearance. If it conflicts,
use the side radiator position as intake and keep the front bank installed.

References:

- [Corsair 4000D quick-start guide](https://assets.corsair.com/image/upload/v1684779868/corsairmedia/sys_master/productcontent/WW_4000D_4000D_Airflow_QSG_AB.pdf)
- [Corsair FRAME 4000 series guide](https://www.corsair.com/us/en/explorer/diy-builder/cases/corsair-frame-4000-series/)
- [ARCTIC Liquid Freezer III Pro 360 specification sheet](https://www.arctic.de/media/e3/d9/86/1741780098/Spec_Sheet_Liquid_Freezer_III_Pro_360_EN.pdf)

## Hardware record

Fill these values from the labels before assembly.

| Component | Planned hardware | Exact model / serial |
| --- | --- | --- |
| Case | Corsair FRAME 4000-series | FRAME 4000D WOOD confirmed |
| CPU | AMD Ryzen 9 9950X | Ryzen 9 9950X confirmed from photo |
| Cooler | ARCTIC Liquid Freezer III Pro 360 A-RGB (confirm) | TODO |
| Motherboard | MSI X870E-class AM5 | MAG X870E TOMAHAWK WIFI confirmed |
| Memory | 96 GB DDR5 (2 x 48 GB) | Corsair; exact kit/SKU TODO |
| NVMe | 1 TB Samsung 990-series | TODO |
| GPU | EVGA GeForce RTX 3090 FTW3 24 GB | TODO |
| PSU | 1000 W-class | TODO |
| Network | 10 GbE | TODO |

Photograph component labels and serial numbers before they become obscured.
Store warranty receipts outside the repository.

## Preparation

- [ ] Work on a stable table, not on carpet.
- [ ] Disconnect power and remove jewellery.
- [ ] Use an ESD strap or regularly touch grounded bare metal.
- [ ] Gather a #2 Phillips screwdriver, side cutters, hook-and-loop ties,
      thermal paste if the cooler does not include it, and a flashlight.
- [ ] Remove both case panels and store the tempered-glass panel on a soft,
      non-tile surface.
- [ ] Confirm that motherboard standoffs match the ATX hole pattern and that no
      extra standoff can contact the back of the motherboard.
- [ ] Inventory all PSU modular cables. Use only cables supplied for this exact
      PSU model.

## Fit check before motherboard installation

- [x] Confirm the FRAME 4000-series chassis layout from the case photo.
- [x] Record the exact case variant: Corsair FRAME 4000D WOOD.
- [ ] Dry-fit the 360 mm radiator and fans at the top as exhaust.
- [ ] Dry-fit the RTX 3090 and verify length, height, side-panel clearance, and
      access to its power connectors.
- [ ] Confirm room for a GPU support bracket without blocking intake airflow.
- [ ] Confirm that the radiator tubes reach the CPU socket without sharp bends
      or pressure on the GPU.
- [x] Select the initial airflow plan: three front fans as intake, top radiator
      as exhaust, and rear fan as exhaust.

## Motherboard bench assembly

- [ ] Place the motherboard on its cardboard box, not on the antistatic bag.
- [ ] Inspect the AM5 socket for damage before installing the CPU.
- [ ] Finish securing the installed Ryzen 9 9950X: the photo shows the load
      plate down but the silver retention arm raised. Press the arm fully down
      and tuck it under its retaining hook before installing the cooler. Save
      the socket cover.
- [ ] Install the Samsung NVMe in the motherboard's preferred CPU-connected
      M2_1 slot beneath the upper TOMAHAWK heatsink.
- [x] Install the two 48 GB DIMMs in slots DIMMA2 and DIMMB2.
- [ ] Install the cooler's AM5 mounting hardware according to the ARCTIC manual.
- [ ] Leave EXPO disabled for the first boot and baseline stability tests.

## Case assembly

- [ ] Install the motherboard and tighten screws only until snug.
- [ ] Install the PSU with its intake facing a filtered vent.
- [ ] Connect the 24-pin ATX and all required CPU EPS power cables before the
      radiator makes the top of the motherboard difficult to reach.
- [ ] Mount the radiator and fans in the verified position.
- [ ] Mount the pump/block evenly using the specified tightening sequence.
- [ ] Connect pump, VRM fan, radiator fans, and A-RGB leads to the documented
      headers.
- [ ] Install the RTX 3090 in the primary x16 slot and add its support bracket.
- [ ] Power each RTX 3090 8-pin input with the PSU cabling recommended by the
      PSU/GPU manuals; avoid an undocumented daisy-chain arrangement.
- [ ] Install the 10 GbE adapter in a slot that does not reduce the GPU link or
      disable the selected M.2 slot, based on the motherboard lane table.
- [ ] Connect front-panel, USB, audio, and case-fan headers.
- [ ] Perform a cable inspection before applying power; keep cables clear of
      every fan.

## First POST evidence

Record these values before closing the case or enabling EXPO.

| Check | Result |
| --- | --- |
| POST successful | TODO |
| CPU detected | TODO |
| Memory detected at baseline JEDEC speed | TODO |
| NVMe detected | TODO |
| RTX 3090 detected | TODO |
| 10 GbE adapter detected | TODO |
| CPU temperature in firmware after 10 minutes | TODO |
| Firmware version | TODO |

Do not proceed to KAN-131 build step 2 until all fans spin, the pump reports a
plausible speed, temperatures are stable, the GPU is supported, and no cable
contacts a fan.
