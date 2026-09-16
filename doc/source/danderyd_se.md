# Danderyds kommun

Support for the household waste collection schedule published by
[Danderyds kommun](https://www.danderyd.se/), Stockholm County, Sweden. Collection is
carried out by Verdis on the municipality's behalf. Data is read from the public
collection calendar ("Hämtningskalender") on danderyd.se — no login is required.

## Configuration via configuration.yaml

```yaml
waste_collection_schedule:
  sources:
    - name: danderyd_se
      args:
        street_address: STREET_ADDRESS
```

### Configuration Variables

**street_address**  
*(String) (required)* Your street address exactly as the Danderyd collection calendar
lists it, including the house number.

## Example

```yaml
waste_collection_schedule:
  sources:
    - name: danderyd_se
      args:
        street_address: <TEST_ADDRESS>
```

## How to get the source arguments

1. Open the [Danderyd collection calendar](https://www.danderyd.se/bygga-bo-och-miljo/avfall-atervinning-och-aterbruk/nar-hamtas-mitt-avfall/).
2. Start typing your street into the address box. Suggestions take a couple of seconds
   to appear.
3. Select your address from the list.
4. Copy the address exactly as shown, including the house number, and use it as
   `street_address`.

If your address does not appear, try adding or removing the space between the street
name and the house number — the calendar matches on the stored address string rather
than a normalised address.

## Notes

Villas and terraced houses have a standard subscription for food and residual waste.
Garden waste and return paper are optional add-on services, so they only appear in the
calendar if the property subscribes to them. From 2026, kerbside packaging collection
("Närsortera") is part of the standard subscription: paper and plastic packaging every
second week, glass and metal every fourth week.

The municipality regenerates the calendar periodically and notes the date it was last
refreshed on the page. Subscription changes made after that date are not reflected until
the next refresh, so a newly added service may take a while to show up in Home Assistant.
