/*
 * Package : Coap
 * Author : S. Hamblett <steve.hamblett@linux.com>
 * Date   : 14/05/2018
 * Copyright :  S.Hamblett
 */

part of coap;

class CoapMessageEncoder18 extends CoapMessageEncoder {
  static CoapILogger _log = new CoapLogManager("console").logger;

  void serialize(CoapDatagramWriter writer, CoapMessage msg, int code) {
    // Write fixed-size CoAP headers
    writer.write(CoapDraft18.version, CoapDraft18.versionBits);
    writer.write(msg.type, CoapDraft18.typeBits);
    writer.write(
        msg.token == null ? 0 : msg.token.length, CoapDraft18.tokenLengthBits);
    writer.write(code, CoapDraft18.codeBits);
    writer.write(msg.id, CoapDraft18.idBits);

    // Write token, which may be 0 to 8 bytes, given by token length field
    writer.writeBytes(msg.token);

    int lastOptionNumber = 0;
    final List<CoapOption> options = msg.getSortedOptions();
    CoapUtil.insertionSort(options, (a, b) => a.type.compareTo(b.type));

    for (CoapOption opt in options) {
      if (opt.type == optionTypeToken) {
        continue;
      }

      // Write 4-bit option delta
      final int optNum = opt.type;
      final int optionDelta = optNum - lastOptionNumber;
      final int optionDeltaNibble = CoapDraft18.getOptionNibble(optionDelta);
      writer.write(optionDeltaNibble, CoapDraft18.optionDeltaBits);

      // Write 4-bit option length
      final int optionLength = opt.length;
      final int optionLengthNibble = CoapDraft18.getOptionNibble(optionLength);
      writer.write(optionLengthNibble, CoapDraft18.optionLengthBits);

      // Write extended option delta field (0 - 2 bytes)
      if (optionDeltaNibble == 13) {
        writer.write(optionDelta - 13, 8);
      } else if (optionDeltaNibble == 14) {
        writer.write(optionDelta - 269, 16);
      }

      // Write extended option length field (0 - 2 bytes)
      if (optionLengthNibble == 13) {
        writer.write(optionLength - 13, 8);
      } else if (optionLengthNibble == 14) {
        writer.write(optionLength - 269, 16);
      }

      // Write option value
      writer.writeBytes(opt.valueBytes);

      lastOptionNumber = optNum;
    }

    if (msg.payload != null && msg.payload.length > 0) {
      // If payload is present and of non-zero length, it is prefixed by
      // an one-byte Payload Marker (0xFF) which indicates the end of
      // options and the start of the payload
      writer.writeByte(CoapDraft18.payloadMarker);
    }
    // Write payload
    writer.writeBytes(msg.payload);
  }
}