module Webpush
  module Encryption
    extend self

    def encrypt(message, p256dh, auth)
      group_name = "prime256v1"
      salt = Random.new.bytes(16)

      server = OpenSSL::PKey::EC.new(group_name)
      server.generate_key
      server_public_key_bn = server.public_key.to_bn

      group = OpenSSL::PKey::EC::Group.new(group_name)
      client_public_key_hex = Base64.decode64(p256dh).unpack("H*").first
      client_public_key_bn = OpenSSL::BN.new(client_public_key_hex, 16)
      client_public_key = OpenSSL::PKey::EC::Point.new(group, client_public_key_bn)

      shared_secret = server.dh_compute_key(client_public_key)

      clientAuthToken = Base64.decode64(auth)

      prk = HKDF.new(shared_secret, :salt => clientAuthToken, :algorithm => 'SHA256', :info => "Content-Encoding: auth\0").next_bytes(32)

      context = create_context(client_public_key_bn, server_public_key_bn)

      content_encryption_key_info = create_info('aesgcm', context)
      content_encryption_key = HKDF.new(prk, :salt => salt, :info => content_encryption_key_info).next_bytes(16)

      nonce_info = create_info('nonce', context)
      nonce = HKDF.new(prk, :salt => salt, :info => nonce_info).next_bytes(12)

      ciphertext = encrypt_payload(message, content_encryption_key, nonce)

      {
        ciphertext: ciphertext,
        salt: salt,
        server_public_key_bn: convert16bit(server_public_key_bn),
        shared_secret: shared_secret
      }
    end
    module_function :encrypt

    def encrypt_2(message, p256dh, auth)
      user_public_key = Base64.urlsafe_decode64(p256dh)
      user_auth = Base64.urlsafe_decode64(auth)

      group_name = "prime256v1"
      salt = Random.new.bytes(16)

      local_curve = OpenSSL::PKey::EC.new(group_name)
      local_curve.generate_key
      user_public_key_point = OpenSSL::PKey::EC::Point.new(local_curve.group, OpenSSL::BN.new(user_public_key, 2))

      shared_secret = local_curve.dh_compute_key(user_public_key_point)
      server_public_key = local_curve.public_key.to_bn.to_s(2)

      ciphertext = ECE.encrypt(message,
        key: shared_secret,
        salt: salt,
        server_public_key: server_public_key,
        user_public_key: user_public_key,
        auth: user_auth)

      {
        ciphertext: ciphertext,
        salt: salt,
        server_public_key_bn: server_public_key,
        shared_secret: shared_secret
      }
    end
    module_function :encrypt_2

    private

    def create_context(clientPublicKey, serverPublicKey)
      c = convert16bit(clientPublicKey)
      s = convert16bit(serverPublicKey)
      context = "\0"
      context += [c.bytesize].pack("n*")
      context += c
      context += [s.bytesize].pack("n*")
      context += s
      context
    end

    def encrypt_payload(plaintext, content_encryption_key, nonce)
      cipher = OpenSSL::Cipher.new('aes-128-gcm')
      cipher.encrypt
      cipher.key = content_encryption_key
      cipher.iv = nonce
      padding = cipher.update("\0\0")
      text = cipher.update(plaintext)

      e_text = padding + text + cipher.final
      e_tag = cipher.auth_tag

      e_text + e_tag
    end

    def create_info(type, context)
      info = "Content-Encoding: "
      info += type
      info += "\0"
      info += "P-256"
      info += context
      info
    end

    def convert16bit(key)
      [key.to_s(16)].pack("H*")
    end

    def unescape_base64(base64)
      base64.gsub(/_|\-/, "_" => "/", "-" => "+")
    end
  end
end
