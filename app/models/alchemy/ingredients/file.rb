# frozen_string_literal: true

module Alchemy
  module Ingredients
    # A link to a file
    #
    # Attach Alchemy::Attachment into this ingredient
    #
    class File < Alchemy::Ingredient
      self.ingredient_attributes = %i[
        css_class
        link_text
        title
      ]

      related_object_alias :attachment

      delegate :name, to: :attachment, allow_nil: true

      # The first 30 characters of the attachments name
      #
      # Used by the Element#preview_text method.
      #
      # @param [Integer] max_length (30)
      #
      def preview_text(max_length = 30)
        attachment&.name.to_s[0..max_length - 1]
      end
    end
  end
end
