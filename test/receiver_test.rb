require 'rubygems'
require 'test/unit'
require 'smpp'

class ReceiverTest < Test::Unit::TestCase

  class RecordingDelegate
    attr_reader :received_pdus, :received_delivery_report_pdus, :states
    def initialize
      @received_pdus, @received_delivery_report_pdus, @states = [], [], []
    end
    def mo_received(receiver, pdu)
      @received_pdus << pdu
    end
    def delivery_report_received(receiver, pdu)
      @received_delivery_report_pdus << pdu
    end
    def bound(receiver)
      @states << :bound
    end
  end

  class ExceptionRaisingDelegate < RecordingDelegate
    def mo_received(receiver, pdu)
      raise "exception in delegate"
    end
  end

  def test_receiving_bind_receiver_response_with_ok_status_should_become_bound
    receiver = build_receiver
    bind_receiver_response = Smpp::Pdu::BindReceiverResponse.new(nil, Smpp::Pdu::Base::ESME_ROK, 1)

    receiver.process_pdu(bind_receiver_response)

    assert receiver.bound?
  end

  def test_receiving_bind_receiver_response_with_ok_status_should_invoke_bound_on_delegate
    delegate = RecordingDelegate.new
    receiver = build_receiver(delegate)
    bind_receiver_response = Smpp::Pdu::BindReceiverResponse.new(nil, Smpp::Pdu::Base::ESME_ROK, 1)

    receiver.process_pdu(bind_receiver_response)

    assert_equal [:bound], delegate.states
  end

  def test_receiving_bind_receiver_response_with_ok_status_should_not_error_if_method_doesnt_exist_on_delegate
    delegate = Object.new
    receiver = build_receiver(delegate)
    bind_receiver_response = Smpp::Pdu::BindReceiverResponse.new(nil, Smpp::Pdu::Base::ESME_ROK, 1)

    assert_nothing_raised { receiver.process_pdu(bind_receiver_response) }
  end

  def test_receiving_bind_receiver_response_with_error_status_should_not_become_bound
    receiver = build_receiver
    bind_receiver_response = Smpp::Pdu::BindReceiverResponse.new(nil, Smpp::Pdu::Base::ESME_RBINDFAIL, 1)

    receiver.process_pdu(bind_receiver_response)

    assert receiver.unbound?
  end

  def test_receiving_bind_receiver_response_with_error_status_should_not_invoke_bound_on_delegate
    delegate = RecordingDelegate.new
    receiver = build_receiver(delegate)
    bind_receiver_response = Smpp::Pdu::BindReceiverResponse.new(nil, Smpp::Pdu::Base::ESME_RBINDFAIL, 1)

    receiver.process_pdu(bind_receiver_response)

    assert_equal [], delegate.states
  end

  def test_receiving_bind_receiver_response_with_error_status_should_close_connection
    receiver = build_receiver
    bind_receiver_response = Smpp::Pdu::BindReceiverResponse.new(nil, Smpp::Pdu::Base::ESME_RBINDFAIL, 1)

    receiver.process_pdu(bind_receiver_response)

    assert_equal 1, receiver.close_connections
  end

  def test_receiving_deliver_sm_should_send_deliver_sm_response
    delegate = RecordingDelegate.new
    receiver = build_receiver(delegate)
    deliver_sm = Smpp::Pdu::DeliverSm.new("from", "to", "message")

    receiver.process_pdu(deliver_sm)

    first_sent_data = receiver.sent_data.first
    assert_not_nil first_sent_data
    actual_response = Smpp::Pdu::Base.create(first_sent_data)
    expected_response = Smpp::Pdu::DeliverSmResponse.new(deliver_sm.sequence_number)
    assert_equal expected_response.to_human, actual_response.to_human
  end

  def test_receiving_deliver_sm_should_send_error_response_if_delegate_raises_exception
    delegate = ExceptionRaisingDelegate.new
    receiver = build_receiver(delegate)
    deliver_sm = Smpp::Pdu::DeliverSm.new("from", "to", "message")

    receiver.process_pdu(deliver_sm)

    first_sent_data = receiver.sent_data.first
    assert_not_nil first_sent_data
    actual_response = Smpp::Pdu::Base.create(first_sent_data)
    expected_response = Smpp::Pdu::DeliverSmResponse.new(deliver_sm.sequence_number, Smpp::Pdu::Base::ESME_RX_T_APPN)
    assert_equal expected_response.to_human, actual_response.to_human
  end

  def test_receiving_deliver_sm_should_still_send_deliver_sm_response_when_no_delegate_is_provided
    delegate = nil
    receiver = build_receiver(delegate)
    deliver_sm = Smpp::Pdu::DeliverSm.new("from", "to", "message")

    receiver.process_pdu(deliver_sm)

    first_sent_data = receiver.sent_data.first
    assert_not_nil first_sent_data
    actual_response = Smpp::Pdu::Base.create(first_sent_data)
    expected_response = Smpp::Pdu::DeliverSmResponse.new(deliver_sm.sequence_number)
    assert_equal expected_response.to_human, actual_response.to_human
  end

  def test_receiving_deliver_sm_should_invoke_mo_received_on_delegate
    delegate = RecordingDelegate.new
    receiver = build_receiver(delegate)
    deliver_sm = Smpp::Pdu::DeliverSm.new("from", "to", "message")

    receiver.process_pdu(deliver_sm)

    first_received_pdu = delegate.received_pdus.first
    assert_not_nil first_received_pdu
    assert_equal deliver_sm.to_human, first_received_pdu.to_human
  end

  def test_receiving_deliver_sm_should_not_error_if_mo_received_method_doesnt_exist_on_delegate
    delegate = Object.new
    receiver = build_receiver(delegate)
    deliver_sm = Smpp::Pdu::DeliverSm.new("from", "to", "message")

    assert_nothing_raised { receiver.process_pdu(deliver_sm) }
  end

  def test_receiving_deliver_sm_for_esm_class_4_should_invoke_delivery_report_received_on_delegate
    delegate = RecordingDelegate.new
    receiver = build_receiver(delegate)
    deliver_sm = Smpp::Pdu::DeliverSm.new("from", "to", "message", :esm_class => 4)

    receiver.process_pdu(deliver_sm)

    first_received_delivery_report_pdu = delegate.received_delivery_report_pdus.first
    assert_not_nil first_received_delivery_report_pdu
    assert_equal deliver_sm.to_human, first_received_delivery_report_pdu.to_human
  end

  def test_receiving_deliver_sm_should_not_error_if_received_delivery_report_method_doesnt_exist_on_delegate
    delegate = Object.new
    receiver = build_receiver(delegate)
    deliver_sm = Smpp::Pdu::DeliverSm.new("from", "to", "message", :esm_class => 4)

    assert_nothing_raised { receiver.process_pdu(deliver_sm) }
  end

  private

  def build_receiver(delegate = nil)
    receiver = Smpp::Receiver.new(1, {}, delegate)
    class << receiver
      attr_reader :sent_data, :close_connections
      def send_data(data)
        @sent_data = (@sent_data || []) + [data]
      end
      def close_connection
        @close_connections = (@close_connections || 0) + 1
      end
    end
    receiver
  end

end
